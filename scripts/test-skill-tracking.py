#!/usr/bin/env python3
import base64
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import threading
import unittest
from unittest.mock import patch
import uuid
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
ORG = '11111111-1111-4111-8111-111111111111'
ORG2 = '22222222-2222-4222-8222-222222222222'


def load(path):
    spec = importlib.util.spec_from_file_location('tracking', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def bearer(sub='user-a'):
    def encode(obj):
        return base64.urlsafe_b64encode(json.dumps(obj).encode()).decode().rstrip('=')
    return 'Bearer ' + encode({'alg': 'RS256'}) + '.' + encode({'sub': sub, 'iss': 'test-issuer'}) + '.synthetic-signature'


class Tracking(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.env = patch.dict(os.environ, {'XDG_STATE_HOME': self.tmp.name, 'QOVERY_SKILLS_NO_TRACKING': ''})
        self.env.start()
        self.m = load(ROOT / '_shared/scripts/skill-run.py')
        self.requests = []

    def tearDown(self):
        self.env.stop()
        self.tmp.cleanup()

    def transport(self, kind, metadata, secret, organization=None, authorization=None):
        self.requests.append(dict(kind=kind, metadata=metadata, secret=secret, organization=organization, authorization=authorization))
        return 202, dict(run_id=metadata['run_id'], event_id=str(uuid.uuid4()), delivery_status='PENDING'), 0

    def test_shared_and_all_distributed_journeys(self):
        paths = [ROOT / '_shared/scripts/skill-run.py', *ROOT.glob('qovery*/scripts/skill-run.py')]
        self.assertEqual(len(paths), 12)
        for source in paths:
            with self.subTest(source=source):
                self.assertEqual(source.read_bytes(), paths[0].read_bytes())
                self.assertEqual(source.with_name('track-skill-usage.sh').read_bytes(), paths[0].with_name('track-skill-usage.sh').read_bytes())
                m = load(source)
                self.requests.clear()
                path = Path(m.start('qovery-signup', 'abc1234'))
                other = Path(m.start('qovery-signup', 'abc1234'))
                self.assertNotEqual(json.loads(path.read_text())['metadata']['run_id'], json.loads(other.read_text())['metadata']['run_id'])
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
                self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)
                m.flush(path, self.transport) # anonymous / abandonment
                with patch.object(m, 'session', return_value=None):
                    m.flush(path, self.transport, ORG) # absent auth, zero association
                self.assertEqual(len(self.requests), 1)
                m.flush(path, self.transport, ORG, (bearer(), 'account-a')) # connected / new account
                m.flush(path, self.transport, ORG, (bearer(), 'account-a')) # same journey resumed
                self.assertEqual(len(self.requests), 2)
                m.flush(path, self.transport, ORG2, (bearer(), 'account-a'))
                m.flush(path, self.transport, ORG, (bearer('user-b'), 'account-b'))
                self.assertEqual(len(self.requests), 2) # immutable association
                first, second = self.requests
                self.assertEqual(first['metadata'], second['metadata'])
                self.assertEqual(first['secret'], second['secret'])
                self.assertRegex(first['secret'], '^[a-f0-9]{64}$')
                self.assertEqual(set(first['metadata']), {'run_id', 'anonymous_id', 'skill_name', 'skill_version', 'started_at'})
                self.assertNotIn('event_id', first['metadata'])
                self.assertIsNone(first['authorization'])
                state = path.read_text()
                self.assertNotIn(bearer(), state)
                self.assertNotIn('user-a', state)
                m.cleanup(path); m.cleanup(other)

    def test_network_retry_preserves_proof_metadata_and_server_event_ids(self):
        path = Path(self.m.start('qovery-onboard', 'abc1234'))
        def failed(*args):
            self.requests.append(args)
            return 0, {}, 0
        with patch.object(self.m.time, 'time', return_value=time.time()):
            self.m.flush(path, failed, ORG, (bearer(), 'account-a'))
            self.assertEqual([x[0] for x in self.requests], ['start', 'associate'])
            self.m.flush(path, failed, ORG, (bearer(), 'account-a'))
            self.assertEqual(len(self.requests), 2) # no immediate retry/sleep
        run = json.loads(path.read_text())
        self.assertGreater(run['start']['next_at'], run['created'])
        with patch.object(self.m.time, 'time', return_value=run['created'] + 100):
            self.m.flush(path, self.transport, ORG, (bearer(), 'account-a'))
        self.assertEqual(self.requests[0][1], self.requests[2]['metadata'])
        self.assertEqual(self.requests[0][2], self.requests[2]['secret'])
        accepted = json.loads(path.read_text())
        self.assertIn('event_id', accepted['start'])
        self.assertIn('event_id', accepted['associate'])
        # A changed account must not flush an old pending association.
        accepted['associate']['status'] = 'pending'; accepted['associate']['next_at'] = 0
        self.m.save(path, accepted)
        count = len(self.requests)
        self.m.flush(path, self.transport, ORG, (bearer('user-b'), 'account-b'))
        self.assertEqual(len(self.requests), count)

    def test_rejections_backoff_and_optout(self):
        for code in (400, 403, 404, 409, 410, 413, 204, 401, 429, 503):
            path = Path(self.m.start('qovery-deploy', 'abc1234'))
            self.m.flush(path, lambda *args: (code, {}, 60))
            item = json.loads(path.read_text())['start']
            self.assertEqual(item['last_http_status'], code)
            self.assertEqual(item['status'], 'pending' if code in (401, 429, 503) else 'stopped')
            if code in (429, 503):
                self.assertGreaterEqual(item['next_at'], time.time() + 59)
        with patch.dict(os.environ, {'QOVERY_SKILLS_NO_TRACKING': '1'}):
            self.assertIsNone(self.m.start('qovery-deploy', 'abc1234'))
            self.m.flush(path, self.transport, ORG, (bearer(), 'a'))
        self.assertFalse(self.requests)
        self.assertIsNone(self.m.start('qovery', 'abc1234'))

    def test_expiration_bounded_queue_and_symlink_protection(self):
        path = Path(self.m.start('qovery-deploy', 'abc1234'))
        path.chmod(0o644)
        with self.assertRaises(ValueError): self.m.flush(path, self.transport)
        path.chmod(0o600)
        original = path.with_name('original'); path.rename(original); path.symlink_to(original)
        with self.assertRaises(OSError): self.m.flush(path, self.transport)
        path.unlink(); original.rename(path)
        with patch.object(self.m, 'MAX_RUNS', 1):
            self.assertIsNone(self.m.start('qovery-deploy', 'abc1234'))
        run = json.loads(path.read_text()); run['created'] = time.time() - self.m.TTL - 1
        self.m.save(path, run)
        self.m.flush(path, self.transport)
        self.assertFalse(path.parent.exists())
        self.assertFalse(self.requests)

    def test_invalid_xdg_uses_home_fallback(self):
        home = Path(self.tmp.name) / 'home'
        for value in ('', 'relative/state'):
            with patch.dict(os.environ, {'XDG_STATE_HOME': value}), patch.object(self.m.Path, 'home', return_value=home):
                path = Path(self.m.start('qovery-deploy', 'abc1234'))
                self.assertTrue(path.is_absolute())
                self.assertEqual(path.parent.parent, home / '.local/state/qovery-skills')
                self.m.flush(path, self.transport)
                self.m.cleanup(path)

    def test_orphaned_launches_do_not_exhaust_queue(self):
        root = self.m.root_dir()
        for i in range(3):
            orphan = root / f'run-orphan-{i}'
            orphan.mkdir(mode=0o700)
            (orphan / '.state-interrupted').write_text('partial')
        with patch.object(self.m, 'MAX_RUNS', 1):
            path = Path(self.m.start('qovery-deploy', 'abc1234'))
        self.assertEqual(list(root.glob('run-*')), [path.parent])

    def test_cleanup_waits_for_worker(self):
        path = Path(self.m.start('qovery-deploy', 'abc1234'))
        entered = threading.Event()
        done = threading.Event()
        errors = []
        def clean():
            entered.set()
            try:
                self.m.cleanup(path)
            except Exception as error:
                errors.append(error)
            finally:
                done.set()
        with self.m.state(path):
            worker = threading.Thread(target=clean)
            worker.start()
            self.assertTrue(entered.wait(1))
            self.assertFalse(done.wait(0.1))
        worker.join(2)
        self.assertTrue(done.is_set())
        self.assertEqual(errors, [])
        self.assertFalse(path.parent.exists())

    def test_auth_uses_supported_cli_and_only_human_bearer_candidates(self):
        def output(value): return subprocess.CompletedProcess([], 0, stdout=value.encode(), stderr=b'')
        with patch.object(self.m.subprocess, 'run', return_value=output(bearer())) as cli:
            header, fingerprint = self.m.session()
            self.assertEqual(header, bearer())
            self.assertEqual(len(fingerprint), 64)
            self.assertEqual(cli.call_args.args[0], ['qovery', 'auth', 'token', '--print', '--authorization-header'])
            self.assertEqual(cli.call_args.kwargs['timeout'], 3)
        for value in ('Token api-secret', 'Bearer invalid', bearer() + '\nextra'):
            with patch.object(self.m.subprocess, 'run', return_value=output(value)):
                self.assertIsNone(self.m.session())

    def test_http_contract_with_mocked_curl_no_real_requests(self):
        path = Path(self.m.start('qovery-deploy', 'abc1234'))
        run = json.loads(path.read_text())
        configs = []
        def curl(args, **kwargs):
            self.assertNotIn(run['secret'], ' '.join(args))
            self.assertNotIn(bearer(), ' '.join(args))
            self.assertEqual(args[:2], ['curl', '--disable'])
            self.assertIn('--max-time', args)
            self.assertEqual(kwargs['timeout'], 9)
            config = kwargs['input'].decode(); configs.append(config)
            Path(args[args.index('--output') + 1]).write_text(json.dumps(dict(run_id=run['metadata']['run_id'], event_id=str(uuid.uuid4()), delivery_status='PENDING')))
            Path(args[args.index('--dump-header') + 1]).write_text('HTTP/1.1 202 Accepted\r\n')
            return subprocess.CompletedProcess(args, 0, stdout=b'202', stderr=b'')
        with patch.object(self.m.subprocess, 'run', side_effect=curl):
            self.m.flush(path, self.m.curl_transport, ORG, (bearer(), 'a'))
        self.assertIn('/v1/skillRuns/start', configs[0])
        self.assertNotIn('Authorization:', configs[0])
        self.assertIn('/v1/organization/' + ORG + '/skillRuns/associate', configs[1])
        self.assertIn('X-Qovery-Skill-Run-Secret:', configs[0])
        self.assertIn('Authorization: Bearer', configs[1])
        for config in configs:
            self.assertIn('User-Agent: QoverySkill/qovery-deploy (version:abc1234; https://github.com/Qovery/qovery-skills)', config)

    def test_cli_simulation_and_development_install(self):
        helper = ROOT / '_shared/scripts/track-skill-usage.sh'
        self.assertEqual(subprocess.check_output(['bash', str(helper), 'start', 'qovery-deploy']), b'')
        output = Path(self.tmp.name) / 'events'
        path = subprocess.check_output(['bash', str(helper), 'start', 'qovery-deploy', '--simulate', str(output)]).decode().strip()
        for _ in range(50):
            if output.exists(): break
            time.sleep(0.02)
        self.assertEqual(json.loads(output.read_text())['kind'], 'start')
        self.assertNotIn(json.loads(Path(path).read_text())['secret'], output.read_text())
        subprocess.check_call(['bash', str(helper), 'cleanup', path])
        self.assertFalse(Path(path).parent.exists())

    def test_debug_contains_no_sensitive_values(self):
        import io
        path = Path(self.m.start('qovery-deploy', 'abc1234'))
        secret = json.loads(path.read_text())['secret']
        stream = io.StringIO()
        with patch.dict(os.environ, {'QOVERY_SKILLS_TRACKING_DEBUG': '1'}), patch.object(sys, 'stderr', stream):
            self.m.flush(path, self.transport, ORG, (bearer(), 'a'))
        self.assertIn('attempted', stream.getvalue())
        self.assertIn('accepted', stream.getvalue())
        self.assertNotIn(secret, stream.getvalue())
        self.assertNotIn(bearer(), stream.getvalue())
        self.assertNotIn(ORG, stream.getvalue())

    def test_nonblocking_worker_lock(self):
        path = Path(self.m.start('qovery-deploy', 'abc1234'))
        with self.m.state(path):
            with self.assertRaises(BlockingIOError): self.m.flush(path, self.transport)
        self.assertFalse(self.requests)

    def test_association_waits_for_start_worker(self):
        path = Path(self.m.start('qovery-deploy', 'abc1234'))
        start_sending = threading.Event()
        release_start = threading.Event()
        association_entered = threading.Event()
        association_done = threading.Event()
        errors = []

        def transport(*args):
            if args[0] == 'start':
                start_sending.set()
                if not release_start.wait(2):
                    raise AssertionError('start worker was not released')
            return self.transport(*args)

        def starting():
            try:
                self.m.flush(path, transport)
            except Exception as error:
                errors.append(error)

        def associating():
            association_entered.set()
            try:
                self.m.flush(path, transport, ORG, (bearer(), 'account-a'))
            except Exception as error:
                errors.append(error)
            finally:
                association_done.set()

        first = threading.Thread(target=starting)
        second = threading.Thread(target=associating)
        first.start()
        try:
            self.assertTrue(start_sending.wait(1))
            second.start()
            self.assertTrue(association_entered.wait(1))
            self.assertFalse(association_done.wait(0.1))
        finally:
            release_start.set()
            first.join(2)
            if second.ident is not None:
                second.join(2)
        self.assertFalse(first.is_alive())
        self.assertFalse(second.is_alive())
        self.assertEqual(errors, [])
        self.assertEqual([r['kind'] for r in self.requests], ['start', 'associate'])
        run = json.loads(path.read_text())
        self.assertEqual(run['associate']['status'], 'accepted')
        self.assertEqual(run['association']['organization'], ORG)

    def test_installation(self):
        checkout = Path(self.tmp.name) / 'repo'
        shutil.copytree(ROOT, checkout, ignore=shutil.ignore_patterns('.git', '__pycache__'))
        (checkout / '.git').mkdir()
        bin_dir = Path(self.tmp.name) / 'bin'; bin_dir.mkdir()
        git = bin_dir / 'git'; git.write_text('#!/bin/sh\nprintf "abc1234\\n"\n'); git.chmod(0o755)
        env = dict(os.environ, PATH=str(bin_dir)+os.pathsep+os.environ['PATH'])
        subprocess.run(['bash', 'install.sh', '--project'], cwd=checkout, env=env, check=True, stdout=subprocess.DEVNULL)
        for skill in ROOT.glob('qovery*/SKILL.md'):
            target = checkout / '.agents/skills' / skill.parent.name
            self.assertEqual((target / 'scripts/skill-run.py').read_bytes(), (ROOT / '_shared/scripts/skill-run.py').read_bytes())
            self.assertNotIn('__QOVERY_SKILL_DIR__', (target / 'SKILL.md').read_text())
            self.assertEqual((target / '_version.txt').read_text().strip(), 'abc1234')
            # Even installed copies: opt-out before state/network. No production requests.
            result = subprocess.check_output(['bash', str(target / 'scripts/track-skill-usage.sh'), 'start', skill.parent.name], env=dict(env, QOVERY_SKILLS_NO_TRACKING='1'))
            self.assertEqual(result, b'')
        subprocess.run(['bash', 'local-install.sh', '--project'], cwd=checkout, env=env, check=True, stdout=subprocess.DEVNULL)
        target = checkout / '.agents/skills/qovery-deploy'
        self.assertTrue((target / 'scripts').is_symlink())
        self.assertFalse((target / '_version.txt').exists())
        self.assertEqual(subprocess.check_output(['bash', str(target / 'scripts/track-skill-usage.sh'), 'start', 'qovery-deploy'], env=env), b'')

if __name__ == '__main__':
    unittest.main()
