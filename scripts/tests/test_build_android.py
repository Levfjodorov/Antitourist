import importlib.util
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


class BuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

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

    def test_pipeline_refreshes_sources_runs_checks_before_build_and_copies_artifacts(self):
        for folder in ['lib', 'assets', 'test']:
            path = self.root / 'mobile' / folder
            path.mkdir(parents=True)
            (path / 'new.txt').write_text(folder)
        (self.root / 'mobile' / 'pubspec.yaml').write_text('version: 0.5.1+9\n')
        calls = []

        def fake_run(flutter, arguments, cwd):
            calls.append(arguments[:])
            build = self.root / 'build' / 'android-project'
            if arguments[0] == 'create':
                manifest = build / 'android' / 'app' / 'src' / 'main' / 'AndroidManifest.xml'
                manifest.parent.mkdir(parents=True)
                manifest.write_text(MANIFEST)
                (build / 'android' / 'app' / 'build.gradle.kts').write_text('minSdk = flutter.minSdkVersion')
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
             patch.object(builder.subprocess, 'check_output', return_value='{"test":true}'), \
             patch('sys.argv', ['build_android.py']):
            self.assertEqual(builder.main(), 0)
        build = self.root / 'build' / 'android-project'
        self.assertFalse((build / 'test' / 'widget_test.dart').exists())
        self.assertTrue((build / 'test' / 'new.txt').is_file())
        self.assertEqual(calls[1:], [
            ['pub', 'get'], ['pub', 'run', 'flutter_launcher_icons'],
            ['analyze'], ['test', '--reporter', 'expanded'], ['build', 'apk', '--release'],
        ])
        self.assertTrue((self.root / 'dist' / 'AntiTourist-0.5.1-test.apk').is_file())
        self.assertEqual((self.root / 'dist' / 'pubspec.lock').read_text(), 'test lock')
        self.assertEqual((self.root / 'dist' / 'flutter-version.json').read_text(), '{"test":true}')


if __name__ == '__main__':
    unittest.main()
