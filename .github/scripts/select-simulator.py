import json
import os
import subprocess

sdk = subprocess.check_output(
    ['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'], text=True
).strip()
runtime = 'com.apple.CoreSimulator.SimRuntime.iOS-' + sdk.replace('.', '-')
devices = json.loads(subprocess.check_output(
    ['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], text=True
))['devices'].get(runtime, [])
device = next((item for item in devices if item['name'].startswith('iPhone')), None)
if device is None:
    raise SystemExit('No available iPhone simulator for iOS ' + sdk)
print('Selected ' + device['name'] + ' (iOS ' + sdk + ')')
with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
    output.write('device_id=' + device['udid'] + '\n')
