import argparse
import os
import pathlib
import subprocess
import sys
import time

parser = argparse.ArgumentParser()
parser.add_argument('--destination', required=True)
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[2]
log = root / 'ios/build/BackgroundProbe.log'
log.parent.mkdir(parents=True, exist_ok=True)
command = ['xcodebuild', '-project', 'ios/GHealth.xcodeproj', '-scheme', 'GHealth', '-derivedDataPath', 'ios/build/DerivedData', '-destination', args.destination, 'test', '-only-testing:GHealthUITests/GHealthUITests/testBackgroundRefreshProbe']
env = os.environ.copy()
env['TEST_RUNNER_GHEALTH_BG_PROBE'] = '1'
old_pids = set(subprocess.run(['pgrep', '-x', 'GHealth'], capture_output=True, text=True).stdout.split())
with log.open('w') as output:
    process = subprocess.Popen(command, cwd=root, env=env, stdout=output, stderr=subprocess.STDOUT)
    deadline = time.monotonic() + 240
    while 'BG_PROBE_READY' not in log.read_text() and process.poll() is None and time.monotonic() < deadline:
        time.sleep(0.5)
    if 'BG_PROBE_READY' not in log.read_text():
        process.terminate()
        process.wait()
        print(log.read_text()[-5000:])
        sys.exit('Background probe did not reach debugger attach point')
    pids = set(subprocess.run(['pgrep', '-x', 'GHealth'], capture_output=True, text=True).stdout.split()) - old_pids
    if len(pids) != 1:
        process.terminate()
        process.wait()
        sys.exit('Could not identify the fixture app process uniquely')
    expression = 'e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"io.ghealth.app.refresh"]'
    result = subprocess.run(['xcrun', 'lldb', '-b', '-p', pids.pop(), '-o', 'expr -l objc -- @import BackgroundTasks', '-o', expression, '-o', 'process detach'], capture_output=True, text=True, timeout=60)
    (root / 'ios/build/BackgroundProbe-lldb.log').write_text(result.stdout + result.stderr)
    print(result.stdout + result.stderr)
    status = process.wait(timeout=120)
    text = log.read_text()
    if 'BG_PROBE_UNAVAILABLE' in text:
        sys.exit('COULD NOT RUN: BGTaskScheduler error 1; this Simulator runtime does not support background processing')
    if result.returncode or status or 'BG_PROBE_REQUESTS=1' not in text:
        print(text[-5000:])
        sys.exit('Background probe failed')
    print('PASS: debugger simulation made 1 stubbed snapshot request; no live network or cache')
