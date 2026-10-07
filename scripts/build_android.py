#!/usr/bin/env python3
"""Build a testing APK from a generated, isolated Flutter Android project."""
import argparse
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def patch_manifest(path: Path) -> None:
    namespace = 'http://schemas.android.com/apk/res/android'
    ET.register_namespace('android', namespace)
    tree = ET.parse(path)
    root = tree.getroot()
    name = '{' + namespace + '}name'
    if not any(p.get(name) == 'android.permission.INTERNET'
               for p in root.findall('uses-permission')):
        root.insert(0, ET.Element('uses-permission', {name: 'android.permission.INTERNET'}))
    application = root.find('application')
    if application is None:
        raise RuntimeError('Generated Android manifest has no application element')
    application.set('{' + namespace + '}label', 'AntiTourist')
    tree.write(path, encoding='utf-8', xml_declaration=True)


def run(flutter: str, arguments: list[str], cwd: Path) -> None:
    print('flutter ' + ' '.join(arguments), flush=True)
    # Windows .bat launchers require cmd.exe; subprocess quotes the argument list.
    command = [flutter, *arguments]
    if sys.platform == 'win32':
        command = ['cmd.exe', '/d', '/c', *command]
    subprocess.run(command, cwd=cwd, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    flutter = shutil.which('flutter')
    if flutter is None:
        print('Flutter SDK is missing from PATH. Install Flutter and Android SDK first. See docs/ANDROID.md.', file=sys.stderr)
        return 2
    build = ROOT / 'build' / 'android-project'
    if build.exists():
        print('Using existing generated Android project; keeping the local test signing key.', flush=True)
    else:
        build.parent.mkdir(parents=True, exist_ok=True)
        run(flutter, ['create', '--no-pub', '--platforms=android',
            '--org=com.antitourist', '--project-name=antitourist', str(build)], ROOT)
    for folder in ['lib', 'assets', 'test']:
        target = build / folder
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(ROOT / 'mobile' / folder, target)
    shutil.copy2(ROOT / 'mobile' / 'pubspec.yaml', build / 'pubspec.yaml')
    patch_manifest(build / 'android' / 'app' / 'src' / 'main' / 'AndroidManifest.xml')
    if args.prepare_only:
        print('Prepared: ' + str(build))
        return 0
    run(flutter, ['pub', 'get'], build)
    run(flutter, ['analyze'], build)
    run(flutter, ['test'], build)
    run(flutter, ['build', 'apk', '--release'], build)
    apk = build / 'build' / 'app' / 'outputs' / 'flutter-apk' / 'app-release.apk'
    if not apk.is_file():
        raise RuntimeError('Flutter did not produce the expected APK')
    output = ROOT / 'dist'
    output.mkdir(exist_ok=True)
    destination = output / 'AntiTourist-0.1.1-test.apk'
    shutil.copy2(apk, destination)
    # Keep the exact Flutter version and lockfile for reproduction of this build.
    version = subprocess.check_output(
        ['cmd.exe', '/d', '/c', flutter, '--version', '--machine']
        if sys.platform == 'win32' else [flutter, '--version', '--machine'], text=True)
    (output / 'flutter-version.json').write_text(version, encoding='utf-8')
    shutil.copy2(build / 'pubspec.lock', output / 'pubspec.lock')
    print('APK: ' + str(destination))
    print('Test build signed with the Flutter-generated debug key; not a Play Store release.')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (subprocess.CalledProcessError, OSError, RuntimeError) as exc:
        print('Build failed: ' + str(exc), file=sys.stderr)
        raise SystemExit(1)
