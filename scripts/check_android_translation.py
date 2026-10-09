"""Install the smoke APK and require a real native translation and photo plugin."""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

PACKAGE = 'com.antitourist.antitourist'
MARKER = 'ANTITOURIST_TRANSLATION_RESULT='


def adb_command(*arguments: str) -> list[str]:
    # Address the emulator explicitly, including after ADB reconnects.
    return ['adb', '-s', os.environ.get('ANDROID_SERIAL', 'emulator-5554'), *arguments]


def read_logs(*arguments: str, attempts: int = 5) -> str:
    last_error = ''
    for attempt in range(attempts):
        result = subprocess.run(adb_command('logcat', '-d', '-v', 'brief', *arguments),
            text=True, errors='replace', capture_output=True, timeout=25)
        if result.returncode == 0:
            return result.stdout
        last_error = result.stderr or result.stdout or str(result.returncode)
        print('ADB log read failed temporarily: ' + last_error[-1000:], flush=True)
        if attempt + 1 < attempts:
            subprocess.run(adb_command('wait-for-device'), timeout=20, check=False,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(2)
    raise RuntimeError('ADB log reading did not recover: ' + last_error[-1000:])


def result_from_logs(logs: str) -> dict | None:
    for line in logs.splitlines():
        if MARKER in line:
            return json.loads(line.split(MARKER, 1)[1])
    return None


def main() -> None:
    apk = Path(sys.argv[1]).resolve()
    for arguments in [('install', '-r', str(apk)), ('logcat', '-c'),
                      ('shell', 'svc', 'wifi', 'enable'), ('shell', 'svc', 'data', 'enable')]:
        subprocess.run(adb_command(*arguments), check=True, timeout=90)
    time.sleep(3)
    subprocess.run(adb_command('shell', 'am', 'start', '-n', PACKAGE + '/.MainActivity'),
        check=True, timeout=30)
    deadline = time.monotonic() + 720
    logs = ''
    while time.monotonic() < deadline:
        logs = read_logs()
        result = result_from_logs(logs)
        if result is not None:
            print(json.dumps(result, ensure_ascii=False), flush=True)
            if result.get('ok') is True and result.get('photoPickerRegistered') is True:
                return
            print(read_logs('*:E')[-30000:])
            raise RuntimeError('Native translation or photo-picker registration failed')
        time.sleep(3)
    print(logs[-30000:])
    raise RuntimeError('No native translation result within twelve minutes')


if __name__ == '__main__':
    main()
