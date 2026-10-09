"""Install the separate smoke APK and require an actual native Russian translation."""
import json
import subprocess
import sys
import time
from pathlib import Path

package = 'com.antitourist.antitourist'
marker = 'ANTITOURIST_TRANSLATION_RESULT='
apk = Path(sys.argv[1]).resolve()
subprocess.run(['adb', 'install', '-r', str(apk)], check=True)
subprocess.run(['adb', 'logcat', '-c'], check=True)
subprocess.run(['adb', 'shell', 'svc', 'wifi', 'disable'], check=True)
subprocess.run(['adb', 'shell', 'svc', 'data', 'enable'], check=True)
time.sleep(3)
subprocess.run(['adb', 'shell', 'am', 'start', '-n', package + '/.MainActivity'], check=True)
deadline = time.monotonic() + 720
while time.monotonic() < deadline:
    logs = subprocess.check_output(['adb', 'logcat', '-d', '-v', 'brief'], text=True, errors='replace')
    for line in logs.splitlines():
        if marker in line:
            result = json.loads(line.split(marker, 1)[1])
            print(json.dumps(result, ensure_ascii=False), flush=True)
            if result['ok']:
                raise SystemExit(0)
            # Keep startup registration failures; emulator system logs can push
            # them out of a small tail within seconds.
            pid = subprocess.check_output(['adb', 'shell', 'pidof', package], text=True).strip()
            if pid:
                app_logs = subprocess.check_output(['adb', 'logcat', '-d', '--pid=' + pid, '-v', 'brief'],
                    text=True, errors='replace')
                print(app_logs)
            print(subprocess.check_output(['adb', 'logcat', '-d', '-v', 'brief', '*:E'],
                text=True, errors='replace')[-30000:])
            raise SystemExit('Native translation failed')
    time.sleep(3)
print(logs[-30000:])
raise SystemExit('No native translation result within twelve minutes')
