#!/usr/bin/env python3
"""Build and package the Chinese preview as ZIP and drag-to-install DMG."""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
from build import ROOT


def run(*command, **kwargs):
    subprocess.run([str(part) for part in command], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', type=Path)
    parser.add_argument('--app', type=Path, help='Package an existing app instead of rebuilding (local previews)')
    args = parser.parse_args()
    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    # Separate build/staging directories avoid overwriting another build in this checkout.
    with tempfile.TemporaryDirectory(prefix='compositor-package-') as temporary:
        work = Path(temporary)
        source = args.app
        if source is None:
            command = [sys.executable, ROOT / 'localization/build.py', '--output', work / 'build']
            if args.sdk:
                command += ['--sdk', args.sdk]
            run(*command)
            source = work / 'build/Compositor 中文版.app'
        stage = work / 'image'
        stage.mkdir()
        app = stage / 'Compositor 中文版.app'
        run('ditto', '--norsrc', '--noextattr', source.resolve(), app)
        run('codesign', '--verify', '--deep', '--strict', app)
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        version = info['CompositorZHVersion']
        if not version or any(c not in '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-' for c in version):
            raise SystemExit('Unsafe or empty app version')
        name = f'Compositor-ZH-{version}-arm64'
        archive = work / f'{name}.zip'
        run('ditto', '-c', '-k', '--keepParent', '--norsrc', '--noextattr', app, archive,
            env={**os.environ, 'COPYFILE_DISABLE': '1'})
        (stage / 'Applications').symlink_to('/Applications')
        (stage / '安装说明.txt').write_text(
            'Compositor 中文版安装说明\n\n'
            '需要 Apple Silicon（M 系列）Mac 和 macOS 26 或更新版本。\n'
            '1. 将「Compositor 中文版.app」拖入旁边的 Applications（应用程序）。\n'
            '2. 从「应用程序」打开软件。更新前请保存项目并退出旧版，再选择替换。\n'
            '3. 若提示无法验证开发者，请到「系统设置 → 隐私与安全性」点击「仍要打开」，按提示确认。\n'
            '4. 安装完成后可推出此磁盘，并删除下载的 DMG。\n\n'
            '本预览版仅有 ad-hoc 签名，没有 Developer ID 签名及 Apple 公证。\n'
            '无需关闭 Gatekeeper；如提示应用损坏，请重新下载或反馈问题。\n'
            'https://github.com/qidian2022/Compositor-ZH/releases\n', encoding='utf-8')
        dmg = work / f'{name}.dmg'
        run('hdiutil', 'create', '-volname', f'Compositor 中文版 {version}',
            '-srcfolder', stage, '-format', 'UDZO', '-fs', 'HFS+', dmg)
        run('hdiutil', 'verify', dmg)
        for artifact in (archive, dmg):
            run('ditto', artifact, dist / artifact.name)
            print(f'Packaged: {dist / artifact.name}', flush=True)
        # Release checksums cover only the two artifacts produced by this invocation.
        packages = [dist / archive.name, dist / dmg.name]
        (dist / 'SHA256SUMS.txt').write_text(''.join(
            f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n' for path in packages))


if __name__ == '__main__':
    main()
