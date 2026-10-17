#!/usr/bin/env python3
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

FAKE_XCRUN = r'''#!/usr/bin/python3
import json,os,sys
from pathlib import Path
a=sys.argv[1:]
def value(flag):return a[a.index(flag)+1]
state=Path(os.environ['FAKE_STATE'])
if a[:2]==['xctrace','record']:
 out=Path(value('--output'));out.mkdir()
 state.write_text(json.dumps({'mode':out.stem,'run_id':value('-ProfileRunID')}))
 with Path(os.environ['FAKE_RECORDS']).open('a') as f:f.write(json.dumps(a)+'\n')
elif a[:4]==['devicectl','device','copy','from']:
 d=json.loads(state.read_text());run_id='stale' if os.environ.get('FAKE_STALE') else d['run_id']
 rows=[{'flow':'stressSearchEmpty','run_id':run_id,'status':'started'}]
 rows += [{'flow':'stressSearchEmpty','run_id':run_id,'status':'iteration_completed','iteration':i} for i in range(1,21)]
 rows += [{'flow':'stressSearchEmpty','run_id':run_id,'status':'completed'}]
 Path(value('--destination')).write_text('\n'.join(json.dumps(r) for r in rows)+'\n')
elif a[:2]==['xctrace','export']:
 if '--toc' in a:
  print('<trace-toc><run number="1"><data><table schema="OSSignpostIntervals"/><table schema="time-profile"/><table schema="potential-hangs" hangs-threshold="250"/></data></run></trace-toc>')
 else:
  xpath=value('--xpath')
  if 'OSSignpostIntervals' in xpath:
   print('<trace-query-result><node><schema><col><mnemonic>duration</mnemonic></col><col><mnemonic>name</mnemonic></col><col><mnemonic>subsystem</mnemonic></col><col><mnemonic>end-process</mnemonic></col></schema><row><duration>20000000000</duration><signpost-name fmt="flow.stressSearchEmpty"/><subsystem>com.TrialByFyre.NextSeason</subsystem><process fmt="NextSeason"/></row></node></trace-query-result>')
  elif 'time-profile' in xpath:
   print('<trace-query-result><node><row><weight>1000000</weight><tagged-backtrace><frame name="Main()"/></tagged-backtrace></row></node></trace-query-result>')
  else:
   row='<row><duration>1128000000</duration><process fmt="NextSeason"/></row>' if Path(value('--input')).stem=='instrumented' else ''
   print('<trace-query-result><node><schema/>'+row+'</node></trace-query-result>')
'''


class StressComparisonTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.api = runpy.run_path(str(ROOT / 'Scripts/analyze-stress-comparison.py'))

    def markers(self, run_id='current'):
        base = {'flow': 'stressSearchEmpty', 'run_id': run_id}
        return [{**base, 'status': 'started'}] + [
            {**base, 'status': 'iteration_completed', 'iteration': i} for i in range(1, 21)
        ] + [{**base, 'status': 'completed'}]

    def gaps(self, rows):
        p = self.tmp / 'outcomes.jsonl'
        p.write_text('\n'.join(json.dumps(r) for r in rows))
        return self.api['outcome_gaps'](p, 'current')

    def test_twenty_current_run_searches_complete(self):
        self.assertEqual(self.gaps(self.markers()), [])

    def test_old_run_does_not_prove_completion(self):
        self.assertTrue(self.gaps(self.markers('old')))

    def test_missing_duplicate_and_out_of_order_iterations_fail(self):
        for kind in ('missing', 'duplicate', 'out of order', 'duplicate start'):
            with self.subTest(kind=kind):
                rows = self.markers()
                if kind == 'missing': rows.pop(5)
                elif kind == 'duplicate': rows.insert(5, rows[5])
                elif kind == 'duplicate start': rows.insert(1, rows[0])
                else: rows[3],rows[4] = rows[4],rows[3]
                self.assertTrue(self.gaps(rows))

    def test_failure_after_twenty_searches_is_not_success(self):
        rows = self.markers()
        rows[-1] = {**rows[-1], 'status': 'failed', 'error': 'timeout'}
        self.assertIn('timeout', self.gaps(rows))

    def run_script(self, stale=False):
        shutil.copytree(ROOT / 'Scripts', self.tmp / 'Scripts')
        bin_dir = self.tmp / 'bin';bin_dir.mkdir()
        fake = bin_dir / 'xcrun';fake.write_text(FAKE_XCRUN);fake.chmod(0o755)
        app = self.tmp / 'NextSeason.app';app.mkdir()
        records = self.tmp / 'recordings'
        env = {**os.environ, 'PATH': str(bin_dir)+':/usr/bin:/bin:/usr/sbin:/sbin',
               'PROFILE_PYTHON': sys.executable, 'SKIP_BUILD': '1', 'APP_PATH': str(app),
               'DEVICE_UDID': 'PHYSICAL-DEVICE', 'FAKE_STATE': str(self.tmp/'state'),
               'FAKE_RECORDS': str(records)}
        if stale:env['FAKE_STALE'] = '1'
        result = subprocess.run(['bash', str(self.tmp/'Scripts/profile-stress-comparison.sh')],
                                env=env,capture_output=True,text=True,timeout=20)
        session = next((self.tmp/'.instruments').iterdir())
        return result, json.loads((session/'comparison.json').read_text()), [json.loads(s) for s in records.read_text().splitlines()]

    def test_paired_script_uses_same_flow_and_correct_instruments(self):
        result, report, recordings = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(report['complete'])
        self.assertEqual(len(recordings), 2)
        self.assertNotIn('--instrument', recordings[0])
        self.assertIn('Leaks', recordings[1])
        self.assertEqual(report['runs']['time-profiler']['recorded_hangs'], 0)
        self.assertEqual(report['runs']['instrumented']['recorded_hangs'], 1)
        self.assertTrue(all('stressSearchEmpty' in args for args in recordings))
        self.assertNotEqual(recordings[0][-1], recordings[1][-1])

    def test_stale_file_stops_before_second_recording(self):
        result, report, recordings = self.run_script(stale=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(report['complete'])
        self.assertEqual(len(recordings), 1)


if __name__ == '__main__':
    unittest.main()
