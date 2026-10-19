#!/usr/bin/env python3
"""Rebuild, verify and package the Chinese preview without build caches."""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import sys
from build import ROOT, VERSION

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sdk', type=Path)
args = parser.parse_args()
command = [sys.executable, str(ROOT / 'localization/build.py')]
if args.sdk:
    command += ['--sdk', str(args.sdk)]
subprocess.run(command, check=True)
app = ROOT / 'build/Compositor 中文版.app'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
dist = ROOT / 'dist'
dist.mkdir(exist_ok=True)
archive = dist / f'Compositor-ZH-{VERSION}-arm64.zip'
archive.unlink(missing_ok=True)
subprocess.run(['ditto', '-c', '-k', '--keepParent', '--norsrc', '--noextattr', str(app), str(archive)],
               check=True, env={**os.environ, 'COPYFILE_DISABLE': '1'})
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
(dist / 'SHA256SUMS.txt').write_text(f'{digest}  {archive.name}\n')
print(f'Packaged {archive.name}: {digest}')
