#!/usr/bin/env python3
"""Offline lifecycle prototype. Fields/identity below are fixtures, NOT an API DTO.
No production transport exists until the q-core contract is validated.
"""
import argparse
import datetime
import fcntl
import json
import os
from pathlib import Path
import re
import stat
import tempfile
import time
import uuid

TTL = 86400

def debug(status):
    if os.environ.get('QOVERY_SKILLS_TRACKING_DEBUG') == '1':
        print('skill-tracking: ' + status, file=__import__('sys').stderr)

def event(name, run):
    return dict(event=name, event_id=str(uuid.uuid4()), timestamp=datetime.datetime.now(datetime.timezone.utc).isoformat(), run_id=run['run_id'], anonymous_fixture_id=run['anonymous_fixture_id'], skill_name=run['skill_name'])

def send(item, transport):
    for attempt in range(3):
        debug('attempted')
        try:
            if transport(item):
                return True
        except Exception:
            pass
        if attempt < 2:
            time.sleep(0.05)
    debug('failed')
    return False

def start(skill, transport):
    if not re.fullmatch(r'[a-zA-Z0-9._-]+', skill):
        raise ValueError('invalid skill')
    run = dict(run_id=str(uuid.uuid4()), anonymous_fixture_id=str(uuid.uuid4()), skill_name=skill, created=time.time(), associations={})
    run['started'] = event('skill-started', run)
    run['started_sent'] = send(run['started'], transport)
    directory = Path(tempfile.mkdtemp(prefix='qovery-skill-run-'))
    path = directory / 'state.json'
    with path.open('x') as stream:
        os.chmod(path, 0o600)
        json.dump(run, stream)
    return str(path)

def resume(path, transport, account=None, organization=None, cleanup=False):
    path = Path(path)
    parent = path.parent.lstat()
    if not stat.S_ISDIR(parent.st_mode) or parent.st_uid != os.getuid() or stat.S_IMODE(parent.st_mode) != 0o700:
        raise ValueError('unsafe state directory')
    fd = os.open(path, os.O_RDWR | os.O_NOFOLLOW)
    with os.fdopen(fd, 'r+') as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600:
            raise ValueError('unsafe state file')
        fcntl.flock(stream, fcntl.LOCK_EX)
        run = json.load(stream)
        if cleanup:
            path.unlink()
            return
        if time.time() - run['created'] > TTL:
            path.unlink()
            raise ValueError('expired state')
        if not run['started_sent']:
            run['started_sent'] = send(run['started'], transport)
        if account and organization and run['started_sent']:
            # Opaque test identities only. Real authentication/identity comes from q-core.
            key = json.dumps([account, organization])
            association = run['associations'].get(key)
            if association is None:
                association = dict(payload=event('skill-run-associated', run), sent=False)
                association['payload'].update(account_fixture=account, organization_fixture=organization)
                run['associations'][key] = association
            if not association['sent']:
                association['sent'] = send(association['payload'], transport)
        stream.seek(0)
        json.dump(run, stream)
        stream.truncate()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['start', 'resume', 'associate', 'cleanup'])
    parser.add_argument('value')
    parser.add_argument('--simulate', help='offline event output file; never a network URL')
    parser.add_argument('--account-fixture')
    parser.add_argument('--organization-fixture')
    args = parser.parse_args()
    if args.action == 'cleanup':
        path = Path(args.value)
        # Validate permissions/expiry without sending before deleting.
        resume(path, lambda _: False, cleanup=True)
        path.parent.rmdir()
        return
    if os.environ.get('QOVERY_SKILLS_NO_TRACKING') or not args.simulate:
        debug('ignored (opt-out or contract unavailable)')
        return
    def transport(item):
        fd = os.open(args.simulate, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'a') as output:
            output.write(json.dumps(item) + '\n')
        return True
    if args.action == 'start':
        print(start(args.value, transport))
    else:
        resume(args.value, transport, args.account_fixture if args.action == 'associate' else None, args.organization_fixture if args.action == 'associate' else None)

if __name__ == '__main__':
    try:
        main()
    except Exception:
        debug('failed')
    # Best effort: never fail the skill, never print exception data.
