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
subprocess.run(['adb', 'shell', 'am', 'start', '-n', package + '/.MainActivity'], check=True)
deadline = time.monotonic() + 420
while time.monotonic() < deadline:
    logs = subprocess.check_output(['adb', 'logcat', '-d', '-v', 'brief'], text=True, errors='replace')
    for line in logs.splitlines():
        if marker in line:
            result = json.loads(line.split(marker, 1)[1])
            print(json.dumps(result, ensure_ascii=False), flush=True)
            if result['ok']:
                raise SystemExit(0)
            print(logs[-30000:])
            raise SystemExit('Native translation failed')
    time.sleep(3)
print(logs[-30000:])
raise SystemExit('No native translation result within seven minutes')
