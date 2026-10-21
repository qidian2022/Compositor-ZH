#!/usr/bin/env python3
"""Run crop regressions against production Swift sources without requiring full Xcode."""
import argparse
import os
from pathlib import Path
import subprocess
from generate import ROOT

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sdk', type=Path)
args = parser.parse_args()
sdk = args.sdk or os.environ.get('SDKROOT') or subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
build = ROOT / 'build/crop-tests'
build.mkdir(parents=True, exist_ok=True)
def run(command, **kwargs):
    subprocess.run([str(x) for x in command], check=True, **kwargs)
objects = []
for source in sorted((ROOT / 'Compositor').rglob('*.c')):
    target = build / (source.stem + '.o')
    run(['xcrun', 'clang', '-c', '-O3', '-arch', 'arm64', '-isysroot', sdk, '-mmacosx-version-min=26.0', source, '-o', target])
    objects.append(target)
sources = sorted(p for p in (ROOT / 'Compositor').rglob('*.swift') if p.name != 'CompositorApp.swift')
command = ['xcrun', 'swiftc', '-sdk', sdk, '-swift-version', '5', '-default-isolation', 'MainActor',
           '-enable-upcoming-feature', 'NonisolatedNonsendingByDefault',
           '-enable-upcoming-feature', 'InferIsolatedConformances',
           '-enable-upcoming-feature', 'MemberImportVisibility', '-module-name', 'Compositor',
           '-target', 'arm64-apple-macosx26.0', '-O', '-whole-module-optimization',
           '-module-cache-path', build / 'ModuleCache',
           '-import-objc-header', ROOT / 'Compositor/Compositor-Bridging-Header.h',
           *sources, ROOT / 'localization/tests/CropRegression.swift', *objects, '-o', build / 'CropRegression']
print('Compiling crop regressions against production sources...', flush=True)
with (build / 'compile.log').open('w') as log:
    try:
        run(command, stdout=log, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError:
        print((build / 'compile.log').read_text()[-14000:])
        raise
run([build / 'CropRegression'])
