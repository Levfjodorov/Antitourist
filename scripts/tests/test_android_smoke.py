import subprocess
import unittest
from unittest.mock import patch
from scripts.check_android_translation import adb_command, read_logs, result_from_logs


class SmokeTests(unittest.TestCase):
    def test_transient_adb_disconnect_is_retried_without_losing_the_native_result(self):
        failed = subprocess.CompletedProcess([], 255, stdout='', stderr='device offline')
        reconnected = subprocess.CompletedProcess([], 0)
        completed = subprocess.CompletedProcess([], 0,
            stdout='I/flutter: ANTITOURIST_TRANSLATION_RESULT={"ok":true,"photoPickerRegistered":true}', stderr='')
        with patch('scripts.check_android_translation.subprocess.run', side_effect=[failed, reconnected, completed]) as run:
            with patch('scripts.check_android_translation.time.sleep'):
                result = result_from_logs(read_logs())
        self.assertTrue(result['ok'])
        self.assertTrue(result['photoPickerRegistered'])
        self.assertIn('wait-for-device', run.call_args_list[1].args[0])

    def test_a_permanent_adb_failure_is_not_reported_as_a_success(self):
        failed = subprocess.CompletedProcess([], 255, stdout='', stderr='device offline')
        with patch('scripts.check_android_translation.subprocess.run', return_value=failed):
            with patch('scripts.check_android_translation.time.sleep'):
                with self.assertRaisesRegex(RuntimeError, 'did not recover'):
                    read_logs(attempts=2)

    def test_emulator_identity_and_native_failure_are_retained(self):
        with patch.dict('os.environ', {'ANDROID_SERIAL': 'emulator-5556'}):
            self.assertEqual(adb_command('logcat'), ['adb', '-s', 'emulator-5556', 'logcat'])
        self.assertFalse(result_from_logs('ANTITOURIST_TRANSLATION_RESULT={"ok":false,"error":"plugin"}')['ok'])
        self.assertIsNone(result_from_logs('unrelated system log'))
