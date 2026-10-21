#!/usr/bin/env python3
"""Build an Apple Silicon app from this checkout; no installed Compositor required."""
import argparse
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
from generate import ROOT, catalog

VERSION = '1.5.3-zh.3'

def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', type=Path, help='macOS SDK directory (or set SDKROOT)')
    parser.add_argument('--output', type=Path, default=ROOT / 'build')
    args = parser.parse_args()
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise SystemExit('An Apple Silicon Mac running macOS 26+ is required.')
    sdk = args.sdk or (Path(os.environ['SDKROOT']) if os.environ.get('SDKROOT') else None)
    if sdk is None:
        sdk = Path(subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip())
    if not sdk.is_dir():
        raise SystemExit(f'SDK not found: {sdk}')
    build = args.output.resolve()
    build.mkdir(parents=True, exist_ok=True)
    print(f'Building {VERSION} with {sdk.name}', flush=True)
    objects = []
    for source in sorted((ROOT / 'Compositor').rglob('*.c')):
        target = build / (source.stem + '.o')
        run('xcrun', 'clang', '-c', '-O3', '-arch', 'arm64', '-isysroot', sdk,
            '-mmacosx-version-min=26.0', source, '-o', target)
        objects.append(target)
    swift = sorted((ROOT / 'Compositor').rglob('*.swift'))
    command = ['xcrun', 'swiftc', '-sdk', sdk, '-swift-version', '5', '-default-isolation', 'MainActor',
               '-enable-upcoming-feature', 'NonisolatedNonsendingByDefault',
               '-enable-upcoming-feature', 'InferIsolatedConformances',
               '-enable-upcoming-feature', 'MemberImportVisibility', '-module-name', 'Compositor',
               '-target', 'arm64-apple-macosx26.0', '-O', '-whole-module-optimization',
               '-module-cache-path', build / 'ModuleCache',
               '-file-prefix-map', f'{ROOT}=/Compositor-ZH',
               '-import-objc-header', ROOT / 'Compositor/Compositor-Bridging-Header.h',
               *swift, *objects, '-o', build / 'Compositor']
    with (build / 'compile.log').open('w') as log:
        try:
            run(*command, stdout=log, stderr=subprocess.STDOUT)
        except subprocess.CalledProcessError:
            print((build / 'compile.log').read_text()[-14000:])
            raise
    app = build / 'Compositor 中文版.app'
    if app.exists():
        shutil.rmtree(app)
    contents = app / 'Contents'
    resources = contents / 'Resources'
    resources.mkdir(parents=True)
    (contents / 'MacOS').mkdir()
    shutil.copy2(build / 'Compositor', contents / 'MacOS/Compositor')
    for source in (ROOT / 'Compositor/Resources').iterdir():
        if source.is_file():
            shutil.copy2(source, resources / source.name)
    (resources / 'ChineseLocalization.json').write_text(json.dumps(catalog(), ensure_ascii=False))
    # Compile a conventional .icns directly from the source PNGs; actool is not in Command Line Tools.
    iconset = build / 'AppIcon.iconset'
    iconset.mkdir(exist_ok=True)
    icons = ROOT / 'Compositor/Assets.xcassets/AppIcon.appiconset'
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            suffix = '@2x' if scale == 2 else ''
            shutil.copy2(icons / f'app-icon-{size * scale}.png', iconset / f'icon_{size}x{size}{suffix}.png')
    run('iconutil', '-c', 'icns', iconset, '-o', resources / 'AppIcon.icns')
    info = plistlib.loads((ROOT / 'Config/Info.plist').read_bytes())
    info.update(CFBundleExecutable='Compositor', CFBundlePackageType='APPL',
                CFBundleIdentifier='io.github.qidian2022.compositor-zh',
                CFBundleName='Compositor 中文版', CFBundleDisplayName='Compositor 中文版',
                CFBundleShortVersionString='1.5.3', CFBundleVersion='15303',
                CompositorZHVersion=VERSION, CFBundleIconFile='AppIcon',
                CFBundleDevelopmentRegion='zh-Hans', CFBundleLocalizations=['zh-Hans', 'en'],
                LSMinimumSystemVersion='26.0', LSArchitecturePriority=['arm64'],
                LSApplicationCategoryType='public.app-category.graphics-design',
                NSHighResolutionCapable=True,
                NSHumanReadableCopyright='Copyright © 2026 Wonder Assembly LLC. MIT License. Independent Chinese fork.')
    for key in list(info):
        if key.startswith('SU'):
            del info[key]
    for document in info.get('CFBundleDocumentTypes', []):
        document['LSHandlerRank'] = 'Alternate'
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
    shutil.copy2(ROOT / 'LICENSE', resources / 'LICENSE-Compositor.txt')
    shutil.copy2(ROOT / 'NOTICE.md', resources / 'NOTICE.md')
    run('codesign', '--force', '--sign', '-', app)
    run('codesign', '--verify', '--deep', '--strict', app)
    print(f'Built: {app}\nAd-hoc signature only; not notarized.', flush=True)

if __name__ == '__main__':
    main()
