import importlib.util
import hashlib
import json
import os
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('builder', Path(__file__).parents[1] / 'build_android.py')
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)

MANIFEST = '''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
<uses-permission android:name="android.permission.INTERNET"/>
<application android:name="${applicationName}" android:label="old">
<activity android:name=".MainActivity" android:exported="true"/>
</application></manifest>'''
ANDROID = '{http://schemas.android.com/apk/res/android}'
KOTLIN = '''android {
    defaultConfig {
        minSdk = flutter.minSdkVersion
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
'''
GROOVY = KOTLIN.replace('minSdk = flutter.minSdkVersion', 'minSdkVersion flutter.minSdkVersion').replace(
    'signingConfigs.getByName("debug")', 'signingConfigs.debug')
CERTIFICATE = 'ab' * 32
BADGING = '''package: name='com.antitourist.antitourist' versionCode='9' versionName='0.5.1'
sdkVersion:'24'
targetSdkVersion:'36'
uses-permission: name='android.permission.INTERNET'
uses-permission: name='android.permission.ACCESS_COARSE_LOCATION'
uses-permission: name='android.permission.ACCESS_FINE_LOCATION'
'''


class BuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / '.flutter-version').write_text('3.47.6\n')

    def test_manifest_permissions_are_idempotent_and_preserve_template(self):
        path = self.root / 'AndroidManifest.xml'
        path.write_text(MANIFEST)
        builder.patch_manifest(path)
        builder.patch_manifest(path)
        root = ET.parse(path).getroot()
        permissions = [p.get(ANDROID + 'name') for p in root.findall('uses-permission')]
        self.assertCountEqual(permissions, ['android.permission.' + p for p in
            ['INTERNET', 'ACCESS_COARSE_LOCATION', 'ACCESS_FINE_LOCATION']])
        app = root.find('application')
        self.assertEqual(app.get(ANDROID + 'name'), '${applicationName}')
        self.assertEqual(app.get(ANDROID + 'label'), 'AntiTourist')
        self.assertEqual(app.find('activity').get(ANDROID + 'exported'), 'true')
        self.assertNotIn('android.permission.ACCESS_BACKGROUND_LOCATION', permissions)

    def test_both_gradle_templates_keep_flutter_minimum_and_patch_once(self):
        for filename, text, expected in [
            ('build.gradle.kts', 'minSdk = flutter.minSdkVersion', 'maxOf(flutter.minSdkVersion, 24)'),
            ('build.gradle', 'minSdkVersion flutter.minSdkVersion', 'Math.max(flutter.minSdkVersion, 24)'),
        ]:
            app = self.root / filename.replace('.', '-')
            app.mkdir()
            path = app / filename
            path.write_text(text)
            builder.patch_min_sdk(app)
            first = path.read_text()
            builder.patch_min_sdk(app)
            self.assertEqual(path.read_text(), first)
            self.assertIn(expected, first)

    def test_apk_name_tracks_pubspec_version(self):
        path = self.root / 'pubspec.yaml'
        path.write_text('name: antitourist\nversion: 0.5.1+9\n')
        self.assertEqual(builder.apk_filename(path), 'AntiTourist-0.5.1-test.apk')
        path.write_text('version: invalid\n')
        with self.assertRaises(RuntimeError):
            builder.apk_filename(path)

    def test_flutter_version_mismatch_stops_before_project_generation(self):
        with patch.object(builder, 'ROOT', self.root), \
             patch.object(builder.subprocess, 'check_output', return_value='{"frameworkVersion":"3.0.0"}'):
            with self.assertRaisesRegex(RuntimeError, 'Use Flutter 3.47.6'):
                builder.flutter_version('/fake/flutter')

    def test_changed_minimum_sdk_template_is_not_silently_ignored(self):
        (self.root / 'build.gradle.kts').write_text('minSdk = 21')
        with self.assertRaisesRegex(RuntimeError, 'Unrecognized minSdk'):
            builder.patch_min_sdk(self.root)

    def test_release_requires_all_credentials_and_existing_keystore(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(RuntimeError, 'Release signing requires'):
                builder.release_certificate()
        with patch.dict(os.environ, {'ANDROID_KEYSTORE_PATH': str(self.root / 'missing.jks'),
            'ANDROID_STORE_PASSWORD': 'store', 'ANDROID_KEY_ALIAS': 'release', 'ANDROID_KEY_PASSWORD': 'key'}):
            with self.assertRaisesRegex(RuntimeError, 'existing keystore'):
                builder.release_certificate()

    def test_certificate_export_keeps_password_out_of_command_arguments(self):
        keystore = self.root / 'release.jks'
        keystore.write_bytes(b'test keystore placeholder')
        with patch.dict(os.environ, {'ANDROID_KEYSTORE_PATH': str(keystore),
            'ANDROID_STORE_PASSWORD': 'private store password', 'ANDROID_KEY_ALIAS': 'release',
            'ANDROID_KEY_PASSWORD': 'private key password'}), \
             patch.object(builder.shutil, 'which', return_value='/fake/keytool'), \
             patch.object(builder.subprocess, 'check_output', return_value=b'certificate') as export:
            self.assertEqual(builder.release_certificate(), hashlib.sha256(b'certificate').hexdigest())
            command = export.call_args.args[0]
            self.assertIn('-storepass:env', command)
            self.assertNotIn('private store password', command)
            self.assertNotIn('private key password', command)

    def test_signing_templates_are_idempotent_and_switch_back_to_debug(self):
        for filename, text in [('build.gradle.kts', KOTLIN), ('build.gradle', GROOVY)]:
            app = self.root / filename.replace('.', '-')
            app.mkdir()
            path = app / filename
            path.write_text(text)
            builder.patch_signing(app, True)
            first = path.read_text()
            builder.patch_signing(app, True)
            self.assertEqual(path.read_text(), first)
            self.assertIn('ANDROID_KEYSTORE_PATH', first)
            self.assertIn('ANDROID_STORE_PASSWORD', first)
            self.assertIn('antitouristRelease', first)
            self.assertNotIn('signingConfigs.debug', first)
            self.assertNotIn('getByName("debug")', first)
            builder.patch_signing(app, False)
            self.assertEqual(path.read_text(), text)

    def test_unrecognized_signing_configuration_is_rejected(self):
        (self.root / 'build.gradle.kts').write_text(KOTLIN.replace('"debug"', '"other"'))
        with self.assertRaisesRegex(RuntimeError, 'Unrecognized signing template'):
            builder.patch_signing(self.root, True)

    def test_apk_signer_and_packaged_manifest_must_match_requested_release(self):
        pubspec = self.root / 'pubspec.yaml'
        pubspec.write_text('version: 0.5.1+9\n')
        apk = self.root / 'app.apk'
        apk.write_bytes(b'APK verification test fixture')
        cases = [
            (CERTIFICATE, 'AntiTourist', CERTIFICATE, BADGING, None),
            (None, 'Android Debug', CERTIFICATE, BADGING, None),
            (CERTIFICATE, 'Android Debug', CERTIFICATE, BADGING, 'permanent keystore'),
            (CERTIFICATE, 'AntiTourist', 'cd' * 32, BADGING, 'permanent keystore'),
            (None, 'AntiTourist', CERTIFICATE, BADGING, 'debug signing'),
            (CERTIFICATE, 'AntiTourist', CERTIFICATE, BADGING.replace("versionCode='9'", "versionCode='8'"), 'APK identity'),
            (CERTIFICATE, 'AntiTourist', CERTIFICATE, BADGING.replace("sdkVersion:'24'", "sdkVersion:'21'"), 'minimum SDK'),
            (CERTIFICATE, 'AntiTourist', CERTIFICATE, BADGING + 'application-debuggable\n', 'release build mode'),
            (CERTIFICATE, 'AntiTourist', CERTIFICATE, BADGING.replace('android.permission.INTERNET', 'other'), 'permissions'),
        ]
        for expected, subject, signer, badging, error in cases:
            with self.subTest(expected=expected, subject=subject, error=error), \
                 patch.object(builder, 'android_tool', side_effect=lambda name: name), \
                 patch.object(builder.subprocess, 'check_output', side_effect=[
                     'Signer #1 certificate DN: CN=' + subject + '\nSigner #1 certificate SHA-256 digest: ' + signer + '\n',
                     badging]):
                if error:
                    with self.assertRaisesRegex(RuntimeError, error):
                        builder.verify_apk(apk, pubspec, expected)
                else:
                    result = builder.verify_apk(apk, pubspec, expected)
                    self.assertEqual(result['version_code'], 9)
                    self.assertEqual(result['signing'], 'release' if expected else 'debug')
                    self.assertEqual(result['certificate_sha256'], CERTIFICATE)

    def test_missing_android_build_tools_are_reported(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(builder.shutil, 'which', return_value=None):
            with self.assertRaisesRegex(RuntimeError, 'missing apksigner'):
                builder.android_tool('apksigner')

    def test_pipeline_refreshes_sources_runs_checks_before_build_and_copies_artifacts(self):
        for folder in ['lib', 'assets', 'test']:
            path = self.root / 'mobile' / folder
            path.mkdir(parents=True)
            (path / 'new.txt').write_text(folder)
        (self.root / 'mobile' / 'pubspec.yaml').write_text('version: 0.5.1+9\n')
        (self.root / 'mobile' / 'pubspec.lock').write_text('test lock')
        calls = []

        def fake_run(flutter, arguments, cwd):
            calls.append(arguments[:])
            build = self.root / 'build' / 'android-project'
            if arguments[0] == 'create':
                manifest = build / 'android' / 'app' / 'src' / 'main' / 'AndroidManifest.xml'
                manifest.parent.mkdir(parents=True)
                manifest.write_text(MANIFEST)
                (build / 'android' / 'app' / 'build.gradle.kts').write_text(KOTLIN)
                (build / 'test').mkdir()
                (build / 'test' / 'widget_test.dart').write_text('stale template test')
            if arguments[:2] == ['pub', 'get']:
                (build / 'pubspec.lock').write_text('test lock')
            if arguments[:2] == ['build', 'apk']:
                apk = build / 'build' / 'app' / 'outputs' / 'flutter-apk' / 'app-release.apk'
                apk.parent.mkdir(parents=True)
                apk.write_bytes(b'simulated APK: not compiled Android code')

        with patch.object(builder, 'ROOT', self.root), \
             patch.object(builder.shutil, 'which', return_value='/fake/flutter'), \
             patch.object(builder, 'run', side_effect=fake_run), \
             patch.object(builder.subprocess, 'check_output', return_value='{"frameworkVersion":"3.47.6"}'), \
             patch.object(builder, 'verify_apk', return_value={'signing': 'debug',
                 'certificate_sha256': CERTIFICATE, 'apk_sha256': 'ef' * 32}), \
             patch('sys.argv', ['build_android.py']):
            self.assertEqual(builder.main(), 0)
        build = self.root / 'build' / 'android-project'
        self.assertFalse((build / 'test' / 'widget_test.dart').exists())
        self.assertTrue((build / 'test' / 'new.txt').is_file())
        self.assertEqual(calls[1:], [
            ['pub', 'get', '--enforce-lockfile'], ['pub', 'run', 'flutter_launcher_icons'],
            ['analyze', '--no-pub'], ['test', '--no-pub', '--reporter', 'expanded'], ['build', 'apk', '--release', '--no-pub'],
        ])
        self.assertTrue((self.root / 'dist' / 'AntiTourist-0.5.1-test.apk').is_file())
        self.assertEqual((self.root / 'dist' / 'pubspec.lock').read_text(), 'test lock')
        self.assertEqual(json.loads((self.root / 'dist' / 'flutter-version.json').read_text()), {'frameworkVersion': '3.47.6'})
        self.assertIn('AntiTourist-0.5.1-test.apk', (self.root / 'dist' / 'SHA256SUMS').read_text())
        self.assertEqual(builder.apk_filename(self.root / 'mobile' / 'pubspec.yaml', True), 'AntiTourist-0.5.1-release.apk')


if __name__ == '__main__':
    unittest.main()
