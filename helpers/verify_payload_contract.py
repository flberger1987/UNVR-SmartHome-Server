#!/usr/bin/env python3
"""Check runtime guard pins against the actual generated compatibility files."""
import hashlib
from pathlib import Path
import re
import sys


def verify(payload):
    guard = (payload / 'guarded-fwupdate').read_text()
    verified = 0
    for target, expected in re.findall(r'require_file_hash\s+([^\s]+)\s+([0-9a-f]{64})', guard):
        target = target.strip('"')
        if target.startswith('$runtime/'):
            relative = target[len('$runtime/'):]
            if relative.startswith(('modules/', 'recovery/', 'drive-bin/real/')):
                continue  # Built or copied on the device, not part of this bundle.
            if relative == 'drive-bin/ubnt-tools':
                relative = 'unifi-drive-ubnt-tools'
        elif target.startswith('/etc/systemd/system/'):
            relative = target[len('/etc/systemd/system/'):]
        else:
            continue  # Stock system binaries are verified separately on device.
        candidate = payload / relative
        if not candidate.is_file() or candidate.is_symlink():
            raise ValueError(f'guard dependency missing or unsafe: {relative}')
        actual = hashlib.sha256(candidate.read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError(f'guard pin differs from payload: {relative}: {expected} != {actual}')
        verified += 1
    if verified < 15:
        raise ValueError('guard parsing found fewer payload contracts than expected')
    print(f'Validated {verified} runtime guard artifact pins')


if __name__ == '__main__':
    verify(Path(sys.argv[1]))
