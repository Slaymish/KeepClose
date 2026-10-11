#!/usr/bin/env python3
"""Sign nested Mach-O files and bundles from the inside out using one identity."""
import argparse
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('bundle', type=Path)
parser.add_argument('identity')
args = parser.parse_args()
root = args.bundle.resolve()
# A secure timestamp needs an Apple-trusted certificate; a local self-signed build
# sets this to "none" because it is deliberately not notarized.
timestamp = os.environ.get('KEEPCLOSE_CODESIGN_TIMESTAMP', '')
options = os.environ.get('KEEPCLOSE_CODESIGN_OPTIONS', 'runtime')
macho = {b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf'}
paths = []
for path in root.rglob('*'):
    if path.is_symlink():
        continue
    if path.is_file():
        with path.open('rb') as stream:
            if stream.read(4) in macho:
                paths.append(path)
    elif path.suffix in {'.framework', '.app', '.xpc'}:
        paths.append(path)
for path in sorted(paths, key=lambda p: len(p.parts), reverse=True) + [root]:
    command = ['codesign', '--force', '--sign', args.identity, '--preserve-metadata=entitlements']
    # The hardened runtime needs an Apple-issued certificate; a local identity omits it.
    if options != 'none':
        command += ['--options', options]
    command.append('--timestamp=none' if timestamp == 'none' else '--timestamp')
    command.append(str(path))
    subprocess.run(command, check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(root)], check=True)
