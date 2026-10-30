#!/usr/bin/env python3
"""Hermetic checks for run-nightly-tests.sh and nightly-test-report.py.

A fake `xcrun` stands in for xcodebuild, simctl, and xcresulttool; Git is real,
in a temporary repository. No simulator or Xcode build is needed.
"""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / 'Scripts/run-nightly-tests.sh'

FAKE_XCRUN = r'''#!/usr/bin/python3
import json, os, sys, time
from pathlib import Path
fake = Path(os.environ['FAKE_DIR'])
args = sys.argv[1:]
with open(fake / 'calls.log', 'a') as log:
    log.write(' '.join(args) + '\n')
tool, rest = args[0], args[1:]

def opt(name):
    return rest[rest.index(name) + 1] if name in rest else None

state = fake / 'devices.json'
devices = json.loads(state.read_text()) if state.exists() else {}
if tool == 'xcodebuild':
    if rest == ['-version']:
        print('Xcode 99.0\nBuild version FAKE1')
    elif rest[0] == 'build-for-testing':
        if os.environ.get('FAKE_BUILD_FAIL'):
            print('error: fake build failure'); sys.exit(65)
        products = Path(opt('-derivedDataPath')) / 'Build/Products'
        products.mkdir(parents=True, exist_ok=True)
        (products / 'NextSeason_SerialTesting_iphonesimulator99.0-arm64.xctestrun').write_text('{}')
    elif rest[0] == 'test-without-building':
        udid = opt('-destination').split('=', 1)[1]
        if os.environ.get('FAKE_HANG') == udid:
            (fake / 'hanging').write_text(udid)
            time.sleep(120)
        outcomes = json.loads(os.environ.get('FAKE_OUTCOMES', '{}'))
        outcome = outcomes.get(udid, {})
        bundle = Path(opt('-resultBundlePath'))
        bundle.mkdir(parents=True)
        failures = outcome.get('failures', [])
        (bundle / 'fake.json').write_text(json.dumps({'passed': outcome.get('passed', 10), 'failures': failures}))
        sys.exit(65 if failures else 0)
elif tool == 'xcresulttool':
    data = json.loads((Path(opt('--path')) / 'fake.json').read_text())
    print(json.dumps({
        'passedTests': data['passed'], 'failedTests': len(data['failures']), 'skippedTests': 0,
        'startTime': 1000.0, 'finishTime': 1100.0,
        'testFailures': [{'testIdentifierString': f[0], 'failureText': f[1]} for f in data['failures']],
    }))
elif tool == 'simctl':
    if rest[:2] == ['list', 'runtimes']:
        print(json.dumps({'runtimes': [
            {'identifier': 'com.apple.CoreSimulator.SimRuntime.iOS-%s' % v.replace('.', '-'),
             'version': v, 'buildversion': 'B' + v, 'platform': 'iOS', 'isAvailable': True}
            for v in ('18.6', '26.5', '27.0')]}))
    elif rest[:2] == ['list', 'devices']:
        print(json.dumps({'devices': devices}))
    elif rest[0] == 'create':
        name, _, runtime = rest[1:4]
        udid = 'UDID-' + runtime.rsplit('.', 1)[1]
        devices.setdefault(runtime, []).append({'name': name, 'udid': udid, 'isAvailable': True})
        state.write_text(json.dumps(devices))
        print(udid)
'''

UDID_18 = 'UDID-iOS-18-6'
UDID_27 = 'UDID-iOS-27-0'
KNOWN_TEST = 'AccessibilityAuditUITests/testKnown()'


def developer_dir():
    return os.environ.get('DEVELOPER_DIR') or subprocess.run(
        ['xcode-select', '-p'], capture_output=True, text=True, check=True).stdout.strip()


class NightlyRunnerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(subprocess.run, ['rm', '-rf', str(self.tmp)])
        self.fake = self.tmp / 'fake'
        bin_dir = self.fake / 'bin'
        bin_dir.mkdir(parents=True)
        xcrun = bin_dir / 'xcrun'
        xcrun.write_text(FAKE_XCRUN)
        xcrun.chmod(0o755)
        self.repo = self.tmp / 'repo with space'
        self.git('init', '-q', '-b', 'main', str(self.repo), cwd=self.tmp)
        (self.repo / 'NextSeason.xcodeproj').mkdir()
        (self.repo / 'NextSeason.xcodeproj/project.pbxproj').write_text('fake')
        (self.repo / 'SerialTesting.xctestplan').write_text('{}')
        (self.repo / '.gitignore').write_text('Config/Secrets.xcconfig\n')
        self.git('add', '.')
        self.git('-c', 'user.name=T', '-c', 'user.email=t@example.com', 'commit', '-qm', 'Fake app')
        self.sha = self.git('rev-parse', 'HEAD').strip()
        # Uncommitted work in the main working copy must be left alone.
        (self.repo / 'Config').mkdir()
        (self.repo / 'Config/Secrets.xcconfig').write_text('KEY = secret\n')
        (self.repo / 'SerialTesting.xctestplan').write_text('{"uncommitted": true}')
        self.known = self.tmp / 'known.txt'
        self.known.write_text('# comment\n%s | 18.6 | iPhone 16 Pro | Known section\n' % KNOWN_TEST)
        self.root = self.tmp / 'nightly'
        self.env = {
            **os.environ,
            'PATH': '%s:%s' % (bin_dir, os.environ['PATH']),
            'FAKE_DIR': str(self.fake), 'REPO_DIR': str(self.repo),
            # /usr/bin/python3 is a shim that needs a real developer directory.
            'NIGHTLY_ROOT': str(self.root), 'DEVELOPER_DIR': developer_dir(),
            'KNOWN_FAILURES_FILE': str(self.known), 'NIGHTLY_SCHEDULED': '0',
        }

    def git(self, *args, cwd=None):
        return subprocess.run(['git', *args], cwd=cwd or self.repo, check=True,
                              capture_output=True, text=True).stdout

    def run_nightly(self, *args, **env):
        return subprocess.run(['bash', str(RUNNER), *args], env={**self.env, **env},
                              capture_output=True, text=True, timeout=60)

    def summary(self):
        latest = self.root / 'latest'
        return (latest / 'summary.md').read_text(), json.loads((latest / 'summary.json').read_text())

    def calls(self, prefix):
        log = self.fake / 'calls.log'
        lines = log.read_text().splitlines() if log.exists() else []
        return [line for line in lines if line.startswith(prefix)]

    def test_all_pass_tests_committed_revision_in_isolation(self):
        status_before = self.git('status', '--porcelain')
        result = self.run_nightly()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        text, data = self.summary()
        self.assertEqual(data['status'], 'PASSED')
        self.assertEqual(data['sha'], self.sha)
        self.assertIn(self.sha, text)
        self.assertEqual([p['os'] for p in data['platforms']], ['18.6', '26.5', '27.0'])
        self.assertEqual(len(self.calls('xcodebuild build-for-testing')), 1)
        self.assertEqual(len(self.calls('xcodebuild test-without-building')), 3)
        for os_version in ('18.6', '26.5', '27.0'):
            self.assertTrue((self.root / 'latest' / ('ios-%s.xcresult' % os_version)).is_dir())
        checkout = self.root / 'checkout'
        self.assertEqual(self.git('rev-parse', 'HEAD', cwd=checkout).strip(), self.sha)
        self.assertEqual((checkout / 'SerialTesting.xctestplan').read_text(), '{}')
        self.assertEqual((checkout / 'Config/Secrets.xcconfig').read_text(), 'KEY = secret\n')
        self.assertEqual(self.git('status', '--porcelain'), status_before)
        self.assertEqual((self.repo / 'SerialTesting.xctestplan').read_text(), '{"uncommitted": true}')
        self.assertFalse((self.root / 'lock').exists())
        self.assertIn('PASSED', (self.root / 'history.log').read_text())

    def test_failures_are_classified_and_compared_with_previous_run(self):
        outcomes = json.dumps({
            UDID_18: {'failures': [[KNOWN_TEST, 'known symptom']]},
            UDID_27: {'failures': [['SearchUITests/testNew()', 'new symptom']]},
        })
        first = self.run_nightly(FAKE_OUTCOMES=outcomes)
        self.assertEqual(first.returncode, 1)
        text, data = self.summary()
        self.assertEqual(data['status'], 'FAILED')
        self.assertIn('2 failing test(s): 1 possibly new, 1 listed known', text)
        by_os = {p['os']: p for p in data['platforms']}
        self.assertEqual(by_os['18.6']['failures'][0]['classification'], 'listed known')
        self.assertEqual(by_os['27.0']['failures'][0]['classification'], 'possibly new')
        self.assertEqual(by_os['26.5']['result'], 'PASSED')
        time.sleep(1.1)  # distinct run ID
        second = self.run_nightly(FAKE_OUTCOMES=outcomes)
        self.assertEqual(second.returncode, 1)
        _, data = self.summary()
        by_os = {p['os']: p for p in data['platforms']}
        self.assertIn('also failed in previous run', by_os['27.0']['failures'][0]['previous'])

    def test_known_test_on_other_device_is_possibly_new(self):
        self.known.write_text('%s | 18.6 | iPhone 16 | Other device\n' % KNOWN_TEST)
        outcomes = json.dumps({UDID_18: {'failures': [[KNOWN_TEST, 'symptom']]}})
        self.run_nightly(FAKE_OUTCOMES=outcomes)
        _, data = self.summary()
        self.assertEqual(data['platforms'][0]['failures'][0]['classification'], 'possibly new')

    def test_build_failure_runs_no_tests(self):
        result = self.run_nightly(FAKE_BUILD_FAIL='1')
        self.assertEqual(result.returncode, 1)
        _, data = self.summary()
        self.assertEqual(data['status'], 'BUILD FAILED')
        self.assertEqual(self.calls('xcodebuild test-without-building'), [])

    def test_unknown_revision_is_a_setup_error(self):
        result = self.run_nightly('--ref', 'no-such-branch')
        self.assertEqual(result.returncode, 2)
        _, data = self.summary()
        self.assertEqual(data['status'], 'ERROR')
        self.assertIn("Cannot resolve revision 'no-such-branch'", data['headline'])

    def test_live_lock_skips_and_stale_lock_is_recovered(self):
        lock = self.root / 'lock'
        lock.mkdir(parents=True)
        (lock / 'pid').write_text(str(os.getpid()))
        busy = self.run_nightly()
        self.assertEqual(busy.returncode, 75)
        _, data = self.summary()
        self.assertEqual(data['status'], 'SKIPPED')
        self.assertTrue(lock.exists())
        self.assertEqual(self.calls('xcodebuild'), [])
        (lock / 'pid').write_text('999999')
        time.sleep(1.1)
        stale = self.run_nightly()
        self.assertEqual(stale.returncode, 0, stale.stdout)
        self.assertFalse(lock.exists())

    def test_start_window_applies_only_to_scheduled_runs(self):
        late = self.run_nightly(NIGHTLY_SCHEDULED='1', NIGHTLY_TEST_TIME='04:01')
        self.assertEqual(late.returncode, 0)
        _, data = self.summary()
        self.assertEqual(data['status'], 'SKIPPED')
        self.assertIn('04:01', data['headline'])
        self.assertEqual(self.calls('xcodebuild'), [])
        for when, window in (('02:00', '02:00-04:00'), ('04:00', '02:00-04:00'), ('00:30', '23:00-01:00')):
            time.sleep(1.1)
            run = self.run_nightly(NIGHTLY_SCHEDULED='1', NIGHTLY_TEST_TIME=when, LATE_START_WINDOW=window)
            self.assertEqual(run.returncode, 0, run.stdout)
            self.assertEqual(self.summary()[1]['status'], 'PASSED', when)
        time.sleep(1.1)
        manual = self.run_nightly(NIGHTLY_TEST_TIME='09:00')
        self.assertEqual(self.summary()[1]['status'], 'PASSED')

    def test_tests_latest_commit_of_checked_out_branch(self):
        self.git('checkout', '-q', '-b', 'feature/work')
        (self.repo / 'feature.txt').write_text('committed')
        self.git('add', 'feature.txt')
        self.git('-c', 'user.name=T', '-c', 'user.email=t@example.com', 'commit', '-qm', 'Feature work')
        feature_sha = self.git('rev-parse', 'HEAD').strip()
        (self.repo / 'feature.txt').write_text('uncommitted edit')
        result = self.run_nightly()
        self.assertEqual(result.returncode, 0, result.stdout)
        text, data = self.summary()
        self.assertEqual((data['branch'], data['sha']), ('feature/work', feature_sha))
        self.assertIn('%s on branch feature/work' % feature_sha, text)
        self.assertEqual((self.root / 'checkout/feature.txt').read_text(), 'committed')
        self.assertEqual((self.repo / 'feature.txt').read_text(), 'uncommitted edit')
        self.assertEqual(self.git('symbolic-ref', '--short', 'HEAD').strip(), 'feature/work')

    def test_detached_head_is_skipped_with_reason(self):
        self.git('checkout', '-q', '--detach')
        result = self.run_nightly()
        self.assertEqual(result.returncode, 0)
        _, data = self.summary()
        self.assertEqual(data['status'], 'SKIPPED')
        self.assertIn('detached HEAD', data['headline'])
        self.assertEqual(self.calls('xcodebuild'), [])

    def test_timeout_stops_a_hung_step_and_continues(self):
        result = self.run_nightly(FAKE_HANG=UDID_18, STEP_TIMEOUT_SECONDS='2')
        self.assertEqual(result.returncode, 1)
        _, data = self.summary()
        by_os = {p['os']: p for p in data['platforms']}
        self.assertEqual(by_os['18.6']['result'], 'TIMED OUT')
        self.assertEqual(by_os['27.0']['result'], 'PASSED')

    def test_interruption_records_partial_results_and_cleans_up(self):
        process = subprocess.Popen(['bash', str(RUNNER)], env={**self.env, 'FAKE_HANG': UDID_18},
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        deadline = time.time() + 30
        while not (self.fake / 'hanging').exists() and time.time() < deadline:
            time.sleep(0.1)
        process.send_signal(signal.SIGTERM)
        process.communicate(timeout=30)
        self.assertEqual(process.returncode, 143)
        _, data = self.summary()
        self.assertEqual(data['status'], 'INTERRUPTED')
        self.assertEqual(data['platforms'][0]['result'], 'INTERRUPTED')
        self.assertFalse((self.root / 'lock').exists())
        self.assertTrue(self.calls('simctl shutdown %s' % UDID_18))
        self.assertEqual(len(self.calls('xcodebuild test-without-building')), 1)

    def test_old_runs_are_pruned_and_simulators_reused(self):
        for day in range(1, 6):
            (self.root / 'runs' / ('2000-01-0%d_020000' % day)).mkdir(parents=True)
        self.run_nightly(KEEP_RUNS='3')
        runs = sorted(os.listdir(self.root / 'runs'))
        self.assertEqual(len(runs), 3)
        self.assertNotIn('2000-01-01_020000', runs)
        self.assertEqual(len(self.calls('simctl create')), 3)
        time.sleep(1.1)
        self.run_nightly(KEEP_RUNS='3')
        self.assertEqual(len(self.calls('simctl create')), 3)

    def test_os_filter_and_only_testing_are_passed_through(self):
        result = self.run_nightly('--os', '27.0', '--only-testing', 'NextSeasonUITests/A/testB()')
        self.assertEqual(result.returncode, 0, result.stdout)
        text, data = self.summary()
        self.assertEqual([p['os'] for p in data['platforms']], ['27.0'])
        self.assertIn('-only-testing:NextSeasonUITests/A/testB()', self.calls('xcodebuild test-without-building')[0])
        self.assertIn('not a full run', text)


if __name__ == '__main__':
    unittest.main()
