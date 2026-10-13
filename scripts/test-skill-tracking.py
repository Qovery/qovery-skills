#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import sys
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]

def load(path):
    spec = importlib.util.spec_from_file_location('tracking', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

class Tracking(unittest.TestCase):
    def test_shared_and_distributed_lifecycle(self):
        paths = [ROOT / '_shared/scripts/skill-run.py', *ROOT.glob('qovery*/scripts/skill-run.py')]
        self.assertEqual(len(paths), 12)
        for source in paths:
            with self.subTest(source=source):
                self.assertEqual(source.read_bytes(), paths[0].read_bytes())
                m = load(source)
                events = []
                def transport(item):
                    events.append(json.loads(json.dumps(item)))
                    return True
                path = Path(m.start('qovery-signup', transport))
                other = Path(m.start('qovery-signup', transport))
                try:
                    self.assertNotEqual(json.loads(path.read_text())['run_id'], json.loads(other.read_text())['run_id'])
                    self.assertEqual(path.stat().st_mode & 0o777, 0o600)
                    self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)
                    m.resume(path, transport) # absent auth / abandonment
                    self.assertEqual(len(events), 2)
                    m.resume(path, transport, 'account-a', 'org-a') # signed in / new account
                    m.resume(path, transport, 'account-a', 'org-a') # resume: no duplicate
                    self.assertEqual(len(events), 3)
                    m.resume(path, transport, 'account-a', 'org-b') # multiple orgs
                    m.resume(path, transport, 'account-b', 'org-b') # changed account
                    self.assertEqual(len(events), 5)
                    self.assertEqual(events[0]['run_id'], events[2]['run_id'])
                    attempts = []
                    def failing(item):
                        attempts.append(json.loads(json.dumps(item)))
                        return False
                    retry = Path(m.start('qovery-onboard', failing))
                    try:
                        m.resume(retry, transport, 'account-a', 'org-a')
                        self.assertEqual(len(attempts), 3)
                        self.assertTrue(all(x == attempts[0] for x in attempts))
                        self.assertEqual(attempts[0], events[-2])
                    finally:
                        shutil.rmtree(retry.parent)
                    state = json.loads(path.read_text()); state['created'] = 0
                    path.write_text(json.dumps(state))
                    with self.assertRaises(ValueError): m.resume(path, transport)
                    self.assertFalse(path.exists())
                finally:
                    shutil.rmtree(path.parent)
                    shutil.rmtree(other.parent)

    def test_cli_optout_contract_gate_and_cleanup(self):
        helper = ROOT / '_shared/scripts/track-skill-usage.sh'
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / 'events'
            args = ['bash', str(helper), 'start', 'qovery', '--simulate', str(output)]
            env = dict(os.environ, QOVERY_SKILLS_NO_TRACKING='1')
            self.assertEqual(subprocess.check_output(args, env=env), b'')
            self.assertFalse(output.exists())
            self.assertEqual(subprocess.check_output(args[:-2]), b'')
            env = dict(os.environ); env.pop('QOVERY_SKILLS_NO_TRACKING', None)
            path = subprocess.check_output(args, env=env).decode().strip()
            subprocess.check_call(['bash', str(helper), 'cleanup', path], env=env)
            self.assertFalse(Path(path).parent.exists())
            self.assertEqual(len(output.read_text().splitlines()), 1)

    def test_failed_start_blocks_association_and_unsafe_state(self):
        m = load(ROOT / '_shared/scripts/skill-run.py')
        attempts = []
        def failing(item):
            attempts.append(dict(item))
            return False
        path = Path(m.start('qovery', failing))
        try:
            m.resume(path, failing, 'account', 'organization')
            self.assertEqual(len(attempts), 6)
            self.assertTrue(all(item == attempts[0] for item in attempts))
            self.assertFalse(json.loads(path.read_text())['associations'])
            path.chmod(0o644)
            with self.assertRaises(ValueError): m.resume(path, failing)
            path.chmod(0o600)
            link = path.parent / 'link'; link.symlink_to(path)
            with self.assertRaises(OSError): m.resume(link, failing)
        finally:
            shutil.rmtree(path.parent)

    def test_installation(self):
        with tempfile.TemporaryDirectory() as tmp:
            checkout = Path(tmp) / 'repo'
            shutil.copytree(ROOT, checkout, ignore=shutil.ignore_patterns('.git', '__pycache__'))
            # Avoid network SHA lookup: installer local .git detection plus fake git.
            (checkout / '.git').mkdir()
            bin_dir = Path(tmp) / 'bin'; bin_dir.mkdir()
            git = bin_dir / 'git'; git.write_text('#!/bin/sh\nprintf "abc1234\\n"\n'); git.chmod(0o755)
            env = dict(os.environ, PATH=str(bin_dir)+os.pathsep+os.environ['PATH'])
            subprocess.run(['bash', 'install.sh', '--project'], cwd=checkout, env=env, check=True, stdout=subprocess.DEVNULL)
            for skill in ROOT.glob('qovery*/SKILL.md'):
                target = checkout / '.agents/skills' / skill.parent.name
                self.assertTrue((target / 'scripts/skill-run.py').exists())
                self.assertNotIn('__QOVERY_SKILL_DIR__', (target / 'SKILL.md').read_text())
                helper = target / 'scripts/track-skill-usage.sh'
                self.assertEqual(subprocess.check_output(['bash', str(helper), 'start', skill.parent.name]), b'')

if __name__ == '__main__':
    unittest.main()
