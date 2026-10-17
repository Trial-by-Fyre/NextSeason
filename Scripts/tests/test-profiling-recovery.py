#!/usr/bin/env python3
"""Hermetic checks for safe profiling-session recovery and the recording watchdog."""
import json
import os
from pathlib import Path
import runpy
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
fixtures = runpy.run_path(str(ROOT / 'Scripts/tests/test-device-log-capture.py'))


class ProfilingRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures['DeviceLogCaptureTests']()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.session = self.fixture.tmp / 'partial-session'
        self.session.mkdir()
        entries = []
        core = ('launch', 'launch-with-data', 'search', 'searchEmpty', 'showDetails',
                'viewWishlist', 'addToWishlist', 'removeFromWishlist')
        runs = [('seedWatchlist', 'seedWatchlist')]
        runs += [(flow, flow + '-run1') for flow in core]
        runs += [('network-' + flow, 'network-' + flow) for flow in ('search', 'showDetails', 'addToWishlist')]
        runs += [(flow, flow) for flow in ('stressSearchDetailsBack', 'stressAddRemoveWishlist', 'stressSearchEmpty')]
        runs += [('stress-launch-with-data', 'stress-launch-with-data-run' + str(i)) for i in range(1, 11)]
        for flow, name in runs:
            trace = self.session / 'traces' / (name + '.trace')
            trace.mkdir(parents=True)
            (trace / 'keep').write_text('completed trace')
            log = self.session / 'logs' / (name + '.log')
            log.parent.mkdir(exist_ok=True)
            log.write_text('completed log')
            entries.append({'flow': flow, 'trace': 'traces/' + name + '.trace', 'log': 'logs/' + name + '.log'})
        self.manifest = {'runs': entries, 'runs_per_flow': 1}
        self.env = {**self.fixture.env, 'SESSION_DIR': str(self.session), 'FAKE_LOG_STREAMS': '1'}

    def damage(self, name):
        self.manifest['runs'] = [r for r in self.manifest['runs'] if r['trace'] != 'traces/' + name + '.trace']
        (self.session / 'manifest.json').write_text(json.dumps(self.manifest))

    def run_suite(self, env=None):
        return subprocess.run(self.fixture.command('profile'), env=env or self.env,
                              capture_output=True, text=True, timeout=20)

    def test_resume_preserves_completed_and_retries_partial(self):
        self.damage('launch-with-data-run1')
        result = self.run_suite()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.fixture.lines('record '), ['record launchWithData'])
        self.assertTrue((self.session / 'traces/launch-run1.trace/keep').exists())
        self.assertFalse((self.session / 'traces/launch-with-data-run1.trace/keep').exists())
        self.assertEqual((self.session / 'logs/launch-run1.log').read_text(), 'completed log')
        after = json.loads((self.session / 'manifest.json').read_text())
        self.assertEqual(len(after['runs']), 25)
        self.assertEqual(len({r['trace'] for r in after['runs']}), 25)

    def test_skip_network_keeps_missing_evidence_incomplete(self):
        for name in ('network-search', 'network-showDetails', 'network-addToWishlist'):
            self.damage(name)
        result = self.run_suite({**self.env, 'SKIP_NETWORK': '1'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.fixture.lines('record '), [])
        report = json.loads((self.session / 'report.json').read_text())
        self.assertEqual(report['readiness'], 'not_established')
        self.assertEqual(report['flows']['network-search']['pass_fail'], 'INCOMPLETE')
        self.assertEqual(json.loads((self.session / 'manifest.json').read_text()), self.manifest)

    def test_timeout_kills_recorder_and_does_not_mark_complete(self):
        self.damage('search-run1')
        fake = self.fixture.tmp / 'bin/xcrun'
        s = fake.read_text().replace('&& sleep 30', "&& { echo \"recorder $$\" >> \"${FAKE_CALLS}\"; exec python3 -c 'import time; time.sleep(60)'; }")
        fake.write_text(s)
        # Shorten only the watchdog's polling sleep, keeping its real control flow.
        sleep = self.fixture.tmp / 'bin/sleep'
        sleep.write_text('#!/bin/bash\nif [[ "$1" == 2 ]]; then exec /bin/sleep 0.05; fi\nexec /bin/sleep "$@"\n')
        sleep.chmod(0o755)
        result = self.run_suite({**self.env, 'FAKE_HANG_FLOW': 'search'})
        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertIn('xctrace hung after 80s', result.stderr)
        after = json.loads((self.session / 'manifest.json').read_text())
        self.assertEqual(after, self.manifest)
        self.fixture.assert_every_stream_stopped_once(1)
        pid = int(self.fixture.lines('recorder ')[0].split()[1])
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)


if __name__ == '__main__':
    unittest.main()
