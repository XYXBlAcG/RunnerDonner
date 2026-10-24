import json
from pathlib import Path
import plistlib
import subprocess
import sys

app = Path(sys.argv[1] if len(sys.argv) > 1 else 'dist/轨迹控制面板.app').resolve()
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
metadata = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert (app / 'Contents/Resources' / (metadata['CFBundleIconFile'] + '.icns')).is_file()
assert (app / 'Contents/Resources/Licenses/eviltransform-LICENSE.txt').is_file()
helper = app / 'Contents/Resources/DeviceBridge/DeviceBridge'
frames = [dict(id='state', command='status'), dict(id='close', command='shutdown')]
result = subprocess.run([str(helper)], input=''.join(json.dumps(frame) + '\n' for frame in frames), capture_output=True, text=True, timeout=20, check=True)
responses = [json.loads(line) for line in result.stdout.splitlines()]
ready = next(value for value in responses if value.get('event') == 'ready')
assert ready['protocol'] == 2
state = next(value for value in responses if value.get('id') == 'state')
assert state['ok'] and state['result']['state'] == 'disconnected'
assert state['result']['capabilities']['canConnect']
assert state['result']['position'] is None
closed = next(value for value in responses if value.get('id') == 'close')
assert closed['ok'] and closed['result']['restored']
print('PASS: package signature, icon, bundled protocol and clean shutdown; no device access')
