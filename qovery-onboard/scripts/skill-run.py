#!/usr/bin/env python3
"""q-core skill run v1. No prompts, CLI cache, or credentials in persisted state."""
import argparse
import base64
import contextlib
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import stat
import subprocess
import sys
import tempfile
import time
import uuid

TTL = 30 * 86400
MAX_RUNS = 100
API = 'https://api.qovery.com'


def debug(status):
    if os.environ.get('QOVERY_SKILLS_TRACKING_DEBUG') == '1':
        print('skill-tracking: ' + status, file=sys.stderr)


def disabled():
    return bool(os.environ.get('QOVERY_SKILLS_NO_TRACKING'))


def private_dir(path):
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError('unsafe directory')


def private_open(path, flags=os.O_RDWR):
    fd = os.open(path, flags | os.O_NOFOLLOW, 0o600)
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600:
        os.close(fd)
        raise ValueError('unsafe file')
    return fd


def root_dir():
    base = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state')))
    root = base / 'qovery-skills'
    root.mkdir(parents=True, mode=0o700, exist_ok=True)
    private_dir(root)
    return root


def save(path, run):
    fd, temporary = tempfile.mkstemp(prefix='.state-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(run, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


@contextlib.contextmanager
def state(path, nonblocking=True):
    path = Path(path).absolute()
    if path.name != 'state.json' or path.parent.parent != root_dir():
        raise ValueError('invalid state location')
    private_dir(path.parent)
    with os.fdopen(private_open(path.parent / 'lock', os.O_RDWR | os.O_CREAT), 'r+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | (fcntl.LOCK_NB if nonblocking else 0))
        with os.fdopen(private_open(path, os.O_RDONLY)) as stream:
            run = json.load(stream)
        yield path, run


def prune(root):
    # Only managed run directories; never follow links or delete unrelated content.
    for directory in root.glob('run-*'):
        try:
            private_dir(directory)
            path = directory / 'state.json'
            with state(path, nonblocking=True) as (_, run):
                if time.time() - run['created'] >= TTL:
                    for name in ('state.json', 'lock'):
                        (directory / name).unlink(missing_ok=True)
                    directory.rmdir()
        except (OSError, ValueError, KeyError):
            continue


def start(skill, version):
    if disabled():
        debug('ignored (opt-out)')
        return None
    if len(skill) > 80 or not re.fullmatch(r'qovery-[a-z0-9][a-z0-9._-]*', skill):
        debug('ignored (unsupported skill)')
        return None
    if len(version) > 80 or not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9._-]*', version):
        raise ValueError('invalid version')
    root = root_dir()
    with os.fdopen(private_open(root / 'queue.lock', os.O_RDWR | os.O_CREAT), 'r+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        prune(root)
        if len(list(root.glob('run-*'))) >= MAX_RUNS:
            debug('ignored (queue full)')
            return None
        directory = Path(tempfile.mkdtemp(prefix='run-', dir=root))
        path = directory / 'state.json'
        run = dict(created=time.time(), secret=secrets.token_hex(32), association=None,
                   metadata=dict(run_id=str(uuid.uuid4()), anonymous_id=str(uuid.uuid4()),
                                 skill_name=skill, skill_version=version,
                                 started_at=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')),
                   start=dict(status='pending', attempts=0, next_at=0))
        save(path, run) # Persist BEFORE any HTTP: retries survive process loss.
        return str(path)


def session():
    # Only the CLI's supported header command; never inspect its cache or print tokens.
    try:
        result = subprocess.run(['qovery', 'auth', 'token', '--print', '--authorization-header'],
                                capture_output=True, timeout=3, check=True)
        header = result.stdout.decode().strip()
        if len(header) > 16384 or not header.startswith('Bearer ') or '\n' in header or '\r' in header:
            return None
        token = header[7:]
        parts = token.split('.')
        if len(parts) != 3:
            return None
        def decode(part):
            return json.loads(base64.urlsafe_b64decode(part + '=' * (-len(part) % 4)))
        claims, algorithm = decode(parts[1]), decode(parts[0])
        if algorithm.get('alg') != 'RS256' or not claims.get('sub') or not claims.get('iss') or claims.get('gty') == 'client-credentials':
            return None
        # Local switch guard ONLY; q-core verifies signature, issuer, human user and permissions.
        fingerprint = hashlib.sha256(json.dumps([claims['iss'], claims['sub']]).encode()).hexdigest()
        return header, fingerprint
    except (OSError, subprocess.SubprocessError, ValueError, KeyError):
        return None


def curl_transport(kind, metadata, secret, organization=None, authorization=None):
    endpoint = '/v1/skillRuns/start' if kind == 'start' else f'/v1/organization/{organization}/skillRuns/associate'
    headers = ['Content-Type: application/json', 'X-Qovery-Skill-Run-Secret: ' + secret]
    if authorization:
        headers.append('Authorization: ' + authorization)
    # Config goes through stdin: neither proof nor Bearer token appears in process argv.
    def quoted(value):
        return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r') + '"'
    with tempfile.TemporaryDirectory(prefix='qovery-tracking-http-') as tmp:
        body, response_headers = Path(tmp) / 'body', Path(tmp) / 'headers'
        config = '\n'.join(['url = ' + quoted(API + endpoint), 'request = "POST"',
                            'data = ' + quoted(json.dumps(metadata)),
                            *['header = ' + quoted(h) for h in headers]])
        try:
            result = subprocess.run(['curl', '--config', '-', '--silent', '--connect-timeout', '3',
                                     '--max-time', '8', '--max-filesize', '4096', '--output', str(body),
                                     '--dump-header', str(response_headers), '--write-out', '%{http_code}'],
                                    input=config.encode(), capture_output=True, timeout=9)
            if result.returncode:
                return 0, {}, 0
            code = int(result.stdout)
            payload = json.loads(body.read_text()) if code == 202 else {}
            retry_after = 0
            for line in response_headers.read_text()[:8192].splitlines():
                if line.lower().startswith('retry-after:'):
                    value = line.split(':', 1)[1].strip()
                    retry_after = int(value) if value.isdigit() else 60
            return code, payload, retry_after
        except (OSError, subprocess.SubprocessError, ValueError):
            return 0, {}, 0


def send(kind, run, transport, authorization=None):
    item = run[kind]
    if item['status'] != 'pending' or time.time() < item['next_at'] or disabled():
        debug('ignored (accepted, stopped, delayed or opt-out)')
        return
    debug('attempted (' + kind + ')')
    try:
        code, response, retry_after = transport(kind, dict(run['metadata']), run['secret'],
                                               run['association']['organization'] if kind == 'associate' else None,
                                               authorization)
    except Exception:
        code, response, retry_after = 0, {}, 0
    if code == 202:
        try:
            uuid.UUID(response['event_id'])
            if response['run_id'] != run['metadata']['run_id'] or response['delivery_status'] not in ('PENDING', 'DELIVERED', 'FAILED'):
                raise ValueError('invalid response')
        except (KeyError, ValueError, TypeError):
            code = 0
        else:
            item.update(status='accepted', event_id=response['event_id'], delivery_status=response['delivery_status'])
            debug('accepted (' + kind + ')')
            return
    if code == 204 or code in (400, 403, 404, 409, 410, 413) or (300 <= code < 500 and code not in (401, 408, 429)):
        item['status'] = 'stopped'
        debug('ignored (opt-out or permanent rejection)')
        return
    item['attempts'] += 1
    # No sleep: persist schedule and retry only on a later opportunistic flush.
    delay = min(3600, 5 * 2 ** min(item['attempts'] - 1, 10) * (0.8 + secrets.randbelow(401) / 1000))
    if code in (429, 503):
        delay = max(delay, 60, retry_after)
    if code == 401:
        delay = max(delay, 5)
    item['next_at'] = time.time() + delay
    debug('failed (queued for retry)')


def flush(path, transport=curl_transport, organization=None, credentials=None):
    if disabled():
        debug('ignored (opt-out)')
        return
    # Explicit association runs in a detached worker: wait for the current
    # sender instead of dropping the handoff. Anonymous queue drains still skip
    # busy runs. HTTP/auth deadlines bound work performed by each lock holder.
    with state(path, nonblocking=organization is None) as (path, run):
        if time.time() - run['created'] >= TTL:
            path.unlink()
            (path.parent / 'lock').unlink()
            path.parent.rmdir()
            debug('ignored (expired)')
            return
        send('start', run, transport)
        save(path, run)
        if organization is None:
            return # Never replay an association under an implicit CLI org/account.
        organization = str(uuid.UUID(organization))
        credentials = credentials or session()
        if not credentials:
            debug('ignored (human auth absent)')
            return
        header, fingerprint = credentials
        target = dict(organization=organization, account_fingerprint=fingerprint)
        if run['association'] is not None and run['association'] != target:
            debug('ignored (account or organization changed; new execution required)')
            return
        if run['association'] is None:
            run['association'] = target
            run['associate'] = dict(status='pending', attempts=0, next_at=0)
            save(path, run)
        # Start is always attempted first; contract allows association while start is queued.
        send('associate', run, transport, header)
        save(path, run)


def cleanup(path):
    with state(path) as (path, _):
        path.unlink()
        (path.parent / 'lock').unlink()
        path.parent.rmdir()


def version():
    try:
        return (Path(__file__).resolve().parent.parent / '_version.txt').read_text().strip()
    except OSError:
        return None # symlinked development installs do not send or create tracking state.


def spawn(path, organization=None, simulate=None):
    command = [sys.executable, str(Path(__file__).resolve()), 'worker', path]
    if organization:
        command += ['--organization', organization]
    if simulate:
        command += ['--simulate', simulate]
    log = sys.stderr if os.environ.get('QOVERY_SKILLS_TRACKING_DEBUG') == '1' else subprocess.DEVNULL
    subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=log,
                     start_new_session=True, close_fds=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['start', 'resume', 'associate', 'cleanup', 'worker'])
    parser.add_argument('value')
    parser.add_argument('--organization')
    parser.add_argument('--simulate', help='offline request recording; no secret/auth is recorded')
    args = parser.parse_args()
    if args.action == 'cleanup':
        cleanup(args.value)
        return
    if disabled():
        debug('ignored (opt-out)')
        return
    installed_version = version()
    if installed_version is None and not args.simulate:
        debug('ignored (development install)')
        return
    if args.action == 'start':
        path = start(args.value, installed_version or 'simulation')
        if path:
            print(path, flush=True)
            spawn(path, simulate=args.simulate)
        return
    if args.action in ('resume', 'associate'):
        if args.action == 'associate' and not args.organization:
            debug('ignored (explicit organization required)')
            return
        spawn(args.value, args.organization if args.action == 'associate' else None, args.simulate)
        return
    transport = curl_transport
    if args.simulate:
        def transport(kind, metadata, secret, organization=None, authorization=None):
            output = Path(args.simulate)
            with os.fdopen(private_open(output, os.O_WRONLY | os.O_CREAT | os.O_APPEND), 'a') as stream:
                fcntl.flock(stream, fcntl.LOCK_EX)
                stream.write(json.dumps(dict(kind=kind, metadata=metadata, organization=organization)) + '\n')
            return 202, dict(run_id=metadata['run_id'], event_id=str(uuid.uuid4()), delivery_status='PENDING'), 0
    flush(args.value, transport, args.organization)
    # Opportunistic anonymous queue drain: bounded to two other runs, never
    # associate an old run using the current account or implicit organization.
    drained = 0
    for directory in sorted(root_dir().glob('run-*')):
        path = directory / 'state.json'
        if str(path) == str(Path(args.value).absolute()):
            continue
        try:
            with state(path) as (_, run):
                due = run['start']['status'] == 'pending' and run['start']['next_at'] <= time.time()
            if due:
                flush(path, transport)
                drained += 1
                if drained == 2:
                    break
        except (OSError, ValueError, KeyError):
            continue


if __name__ == '__main__':
    try:
        main()
    except Exception:
        debug('failed (local state or runtime unavailable)')
    # Do not expose exceptions or fail the skill.
