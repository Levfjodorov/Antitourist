#!/usr/bin/env python3
"""Build and verify a test or permanently signed release APK."""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD_TOOLS_VERSION = '36.0.0'
SIGNING_START = '    // BEGIN ANTITOURIST RELEASE SIGNING\n'
SIGNING_END = '    // END ANTITOURIST RELEASE SIGNING\n'


def tool_command(tool: str, arguments: list[str]) -> list[str]:
    command = [tool, *arguments]
    if sys.platform == 'win32' and Path(tool).suffix.lower() in {'.bat', '.cmd'}:
        command = ['cmd.exe', '/d', '/c', *command]
    return command


def flutter_version(flutter: str) -> dict:
    version = json.loads(subprocess.check_output(
        tool_command(flutter, ['--version', '--machine']), text=True))
    expected = (ROOT / '.flutter-version').read_text(encoding='utf-8').strip()
    if version.get('frameworkVersion') != expected:
        raise RuntimeError('Use Flutter ' + expected + ' from .flutter-version; installed: ' +
                           str(version.get('frameworkVersion')))
    return version


def release_certificate() -> str:
    required = ['ANDROID_KEYSTORE_PATH', 'ANDROID_STORE_PASSWORD',
                'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD']
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise RuntimeError('Release signing requires: ' + ', '.join(missing))
    path = Path(os.environ['ANDROID_KEYSTORE_PATH']).expanduser().resolve()
    if not path.is_file():
        raise RuntimeError('ANDROID_KEYSTORE_PATH must point to an existing keystore')
    os.environ['ANDROID_KEYSTORE_PATH'] = str(path)
    keytool = shutil.which('keytool')
    if keytool is None:
        raise RuntimeError('Release signing requires keytool from the Java JDK')
    # Passwords remain in the environment, never in command arguments or files.
    certificate = subprocess.check_output(tool_command(keytool, [
        '-exportcert', '-keystore', str(path), '-alias', os.environ['ANDROID_KEY_ALIAS'],
        '-storepass:env', 'ANDROID_STORE_PASSWORD']))
    return hashlib.sha256(certificate).hexdigest()


def patch_manifest(path: Path) -> None:
    namespace = 'http://schemas.android.com/apk/res/android'
    ET.register_namespace('android', namespace)
    tree = ET.parse(path)
    root = tree.getroot()
    name = '{' + namespace + '}name'
    permissions = ['INTERNET', 'ACCESS_COARSE_LOCATION', 'ACCESS_FINE_LOCATION']
    existing = {p.get(name) for p in root.findall('uses-permission')}
    for permission in permissions:
        full_name = 'android.permission.' + permission
        if full_name not in existing:
            root.insert(0, ET.Element('uses-permission', {name: full_name}))
    application = root.find('application')
    if application is None:
        raise RuntimeError('Generated Android manifest has no application element')
    application.set('{' + namespace + '}label', 'AntiTourist')
    tree.write(path, encoding='utf-8', xml_declaration=True)


def patch_min_sdk(app: Path) -> None:
    """url_launcher requires Android 7.0; retain higher Flutter defaults."""
    kotlin = app / 'build.gradle.kts'
    groovy = app / 'build.gradle'
    if kotlin.is_file():
        path = kotlin
        original = 'minSdk = flutter.minSdkVersion'
        replacement = 'minSdk = maxOf(flutter.minSdkVersion, 24)'
    elif groovy.is_file():
        path = groovy
        original = 'minSdkVersion flutter.minSdkVersion'
        replacement = 'minSdkVersion Math.max(flutter.minSdkVersion, 24)'
    else:
        raise RuntimeError('Generated Android project has no Gradle app configuration')
    text = path.read_text(encoding='utf-8')
    if text.count(original) == 1:
        text = text.replace(original, replacement)
    elif text.count(replacement) != 1:
        raise RuntimeError('Unrecognized minSdk template; review the generated Gradle configuration')
    path.write_text(text, encoding='utf-8')


def patch_signing(app: Path, release: bool) -> None:
    """Switch signing explicitly, including when a local project is reused."""
    kotlin = app / 'build.gradle.kts'
    groovy = app / 'build.gradle'
    if kotlin.is_file():
        path = kotlin
        debug = 'signingConfig = signingConfigs.getByName("debug")'
        signed = 'signingConfig = signingConfigs.getByName("antitouristRelease")'
        block = '''    signingConfigs {
        create("antitouristRelease") {
            storeFile = file(System.getenv("ANDROID_KEYSTORE_PATH"))
            storePassword = System.getenv("ANDROID_STORE_PASSWORD")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS")
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
        }
    }
'''
    elif groovy.is_file():
        path = groovy
        debug = 'signingConfig = signingConfigs.debug'
        signed = 'signingConfig = signingConfigs.antitouristRelease'
        block = '''    signingConfigs {
        antitouristRelease {
            storeFile = file(System.getenv("ANDROID_KEYSTORE_PATH"))
            storePassword = System.getenv("ANDROID_STORE_PASSWORD")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS")
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
        }
    }
'''
    else:
        raise RuntimeError('Generated Android project has no Gradle app configuration')
    text = path.read_text(encoding='utf-8')
    text = re.sub(re.escape(SIGNING_START) + r'.*?' + re.escape(SIGNING_END),
                  '', text, flags=re.DOTALL).replace(signed, debug)
    if text.count(debug) != 1 or text.count('    buildTypes {') != 1:
        raise RuntimeError('Unrecognized signing template; refusing to guess the release signing configuration')
    if release:
        text = text.replace('    buildTypes {', SIGNING_START + block + SIGNING_END + '    buildTypes {')
        text = text.replace(debug, signed)
    path.write_text(text, encoding='utf-8')


def app_version(pubspec: Path) -> tuple[str, int]:
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
                      pubspec.read_text(encoding='utf-8'), re.MULTILINE)
    if match is None:
        raise RuntimeError('mobile/pubspec.yaml has no supported version')
    return match.group(1), int(match.group(2))


def apk_filename(pubspec: Path, release: bool = False) -> str:
    version, _ = app_version(pubspec)
    return 'AntiTourist-' + version + ('-release.apk' if release else '-test.apk')


def android_tool(name: str) -> str:
    suffix = ('.bat' if name == 'apksigner' else '.exe') if sys.platform == 'win32' else ''
    for variable in ['ANDROID_HOME', 'ANDROID_SDK_ROOT']:
        if not os.environ.get(variable):
            continue
        tool = Path(os.environ[variable]) / 'build-tools' / BUILD_TOOLS_VERSION / (name + suffix)
        if tool.is_file():
            return str(tool)
    raise RuntimeError('Android build-tools ' + BUILD_TOOLS_VERSION + ' are missing ' + name +
                       '; install the pinned build-tools and check ANDROID_HOME')


def verify_apk(apk: Path, pubspec: Path, certificate: str | None) -> dict:
    signing = subprocess.check_output(tool_command(android_tool('apksigner'),
        ['verify', '--verbose', '--print-certs', str(apk)]), text=True)
    signers = re.findall(r'^Signer #\d+ certificate SHA-256 digest:\s*([0-9a-fA-F]{64})\s*$',
                        signing, flags=re.MULTILINE)
    if len(signers) != 1:
        raise RuntimeError('Expected exactly one verified APK signer; apksigner output:\n' + signing)
    signer = signers[0].lower()
    debug = bool(re.search(r'^Signer #\d+ certificate DN:.*\bCN=Android Debug\b',
                           signing, flags=re.MULTILINE))
    if certificate is not None:
        if debug or signer != certificate:
            raise RuntimeError('Release APK must be signed by the selected permanent keystore')
    elif not debug:
        raise RuntimeError('Test APK must use the generated debug signing configuration')
    badging = subprocess.check_output(tool_command(android_tool('aapt'),
        ['dump', 'badging', str(apk)]), text=True)
    package = re.search(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging, re.MULTILINE)
    minimum = re.search(r"^sdkVersion:'(\d+)'", badging, re.MULTILINE)
    version, code = app_version(pubspec)
    if (package is None or minimum is None or
        package.group(1) != 'com.antitourist.antitourist' or
        (package.group(3), int(package.group(2))) != (version, code) or
        int(minimum.group(1)) < 24 or 'application-debuggable' in badging):
        raise RuntimeError('APK identity, version, minimum SDK, or release build mode is incorrect')
    permissions = re.findall(r"^uses-permission: name='([^']+)'", badging, re.MULTILINE)
    required = {'android.permission.' + p for p in
                ['INTERNET', 'ACCESS_COARSE_LOCATION', 'ACCESS_FINE_LOCATION']}
    if not required.issubset(permissions):
        raise RuntimeError('APK is missing required internet/location permissions')
    return {'application_id': package.group(1), 'version_name': version, 'version_code': code,
            'min_sdk': int(minimum.group(1)), 'permissions': permissions,
            'signing': 'release' if certificate is not None else 'debug',
            'certificate_sha256': signer, 'apk_sha256': hashlib.sha256(apk.read_bytes()).hexdigest()}


def run(flutter: str, arguments: list[str], cwd: Path) -> None:
    print('flutter ' + ' '.join(arguments), flush=True)
    subprocess.run(tool_command(flutter, arguments), cwd=cwd, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--release-signing', action='store_true',
                        help='Require permanent signing credentials; never fall back to a debug key')
    args = parser.parse_args()
    flutter = shutil.which('flutter')
    if flutter is None:
        print('Flutter SDK is missing from PATH. Install Flutter and Android SDK first. See docs/ANDROID.md.', file=sys.stderr)
        return 2
    version = flutter_version(flutter)
    certificate = release_certificate() if args.release_signing else None
    pubspec = ROOT / 'mobile' / 'pubspec.yaml'
    lockfile = ROOT / 'mobile' / 'pubspec.lock'
    if not lockfile.is_file():
        raise RuntimeError('mobile/pubspec.lock is required; resolve dependencies with the pinned Flutter SDK')
    app_version(pubspec)
    build = ROOT / 'build' / 'android-project'
    if build.exists():
        print('Refreshing the generated Android project with the pinned Flutter SDK.', flush=True)
        shutil.rmtree(build)
    # Flutter keeps the local debug key in ~/.android, outside this generated project.
    build.parent.mkdir(parents=True, exist_ok=True)
    run(flutter, ['create', '--no-pub', '--platforms=android',
        '--org=com.antitourist', '--project-name=antitourist', str(build)], ROOT)
    for folder in ['lib', 'assets', 'test']:
        target = build / folder
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(ROOT / 'mobile' / folder, target)
    shutil.copy2(pubspec, build / 'pubspec.yaml')
    shutil.copy2(lockfile, build / 'pubspec.lock')
    patch_manifest(build / 'android' / 'app' / 'src' / 'main' / 'AndroidManifest.xml')
    patch_min_sdk(build / 'android' / 'app')
    patch_signing(build / 'android' / 'app', args.release_signing)
    if args.prepare_only:
        print('Prepared: ' + str(build))
        return 0
    run(flutter, ['pub', 'get', '--enforce-lockfile'], build)
    # Generate launcher resources in the isolated project before compiling.
    run(flutter, ['pub', 'run', 'flutter_launcher_icons'], build)
    run(flutter, ['analyze', '--no-pub'], build)
    run(flutter, ['test', '--no-pub', '--reporter', 'expanded'], build)
    run(flutter, ['build', 'apk', '--release', '--no-pub'], build)
    apk = build / 'build' / 'app' / 'outputs' / 'flutter-apk' / 'app-release.apk'
    if not apk.is_file():
        raise RuntimeError('Flutter did not produce the expected APK')
    metadata = verify_apk(apk, pubspec, certificate)
    output = ROOT / 'dist'
    output.mkdir(exist_ok=True)
    # Only remove our previous APKs after a new APK passes verification.
    for previous in output.glob('AntiTourist-*.apk'):
        previous.unlink()
    destination = output / apk_filename(pubspec, args.release_signing)
    shutil.copy2(apk, destination)
    # Keep the exact Flutter version and lockfile for reproduction of this build.
    (output / 'flutter-version.json').write_text(json.dumps(version, indent=2) + '\n', encoding='utf-8')
    (output / 'apk-metadata.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
    shutil.copy2(build / 'pubspec.lock', output / 'pubspec.lock')
    (output / 'SHA256SUMS').write_text(metadata['apk_sha256'] + '  ' + destination.name + '\n', encoding='utf-8')
    print('APK: ' + str(destination))
    print('Verified signing: ' + metadata['signing'] + '; certificate SHA256: ' + metadata['certificate_sha256'])
    if not args.release_signing:
        print('Test build signed with the Flutter-generated debug key; not a Play Store release.')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (subprocess.CalledProcessError, OSError, RuntimeError, ValueError) as exc:
        print('Build failed: ' + str(exc), file=sys.stderr)
        raise SystemExit(1)
