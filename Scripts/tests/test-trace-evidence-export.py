#!/usr/bin/env python3
import json
from pathlib import Path
import runpy
import os
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]

class TraceEvidenceExportTests(unittest.TestCase):
    def setUp(self):
        self.api=runpy.run_path(str(ROOT/'Scripts/export-performance-evidence.py'))
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory=Path(self.temp.name)

    def test_har_directory_merges_exported_files(self):
        for i in range(2):
            (self.directory/f'{i}.har').write_text(json.dumps({'log':{'version':'1.2','entries':[{'request':{'url':f'https://api.tvmaze.com/shows/{i}'}}]}}))
        data=self.api['merge_har_files'](self.directory)
        self.assertEqual(len(data['log']['entries']),2)
        self.assertEqual(data['log']['version'],'1.2')

    def test_missing_empty_and_invalid_har_are_not_evidence(self):
        for value in [None,{},[],{'log':[]},{'log':{'entries':[]}},{'log':{'entries':[{'request':{}}]}},{'log':{'entries':[{'request':{'url':4}}]}}]:
            with self.subTest(value=value):
                p=self.directory/'capture.har'
                if value is not None:p.write_text(json.dumps(value))
                with self.assertRaises(ValueError):self.api['merge_har_files'](self.directory)
                p.unlink(missing_ok=True)

    def test_console_resolves_references_and_preserves_error_levels(self):
        xml='''<trace-query-result><node><row><event-time fmt="00:01"/><process id="1" fmt="NextSeason (123)"/><event-type id="2" fmt="Error"/><subsystem id="3">com.TrialByFyre.NextSeason</subsystem><category id="4">network</category><os-log-metadata id="5" fmt="request failed"/></row><row><event-time fmt="00:02"/><process ref="1"/><event-type ref="2"/><subsystem ref="3"/><category ref="4"/><os-log-metadata ref="5"/></row></node></trace-query-result>'''
        lines=self.api['console_lines'](xml)
        self.assertEqual(len(lines),2)
        self.assertTrue(all('error: request failed' in line for line in lines))

    def test_other_processes_and_har_payloads_are_excluded(self):
        xml='''<trace-query-result><node><row><process fmt="Other (1)"/><os-log-metadata fmt="ignore"/></row><row><process fmt="NextSeason (2)"/><category>HAR</category><os-log-metadata fmt="binary payload"/></row></node></trace-query-result>'''
        self.assertEqual(self.api['console_lines'](xml),[])

    def test_duplicate_table_rows_do_not_duplicate_console_events(self):
        row='<row><process fmt="NextSeason (1)"/><event-time fmt="00:01"/><os-log-metadata fmt="launch"/></row>'
        self.assertEqual(len(self.api['console_lines']('<trace-query-result><node>'+row+row+'</node></trace-query-result>')),1)

    def test_trace_backend_exports_without_native_log_collection(self):
        fake=self.directory/'xcrun'
        fake.write_text('#!/bin/bash\necho \'<trace-query-result><node><row><process fmt="NextSeason (1)"/><event-type fmt="Default"/><os-log-metadata fmt="app launch"/></row></node></trace-query-result>\'\n')
        fake.chmod(0o755)
        output=self.directory/'app.log'
        env={**os.environ,'PATH':str(self.directory)+':/usr/bin:/bin',
             'DEVICE_LOG_CAPTURE_BACKEND':'trace','PROFILE_PYTHON':sys.executable,
             'DEVICE_LOG_CMD':'/must-not-call-native-log'}
        command='source "$1"; device_log_capture_begin phone "$2" predicate; device_log_capture_end 1s saved.trace; device_log_capture_abort'
        result=subprocess.run(['bash','-c',command,'test',str(ROOT/'Scripts/lib/device-log-capture.sh'),str(output)],env=env,capture_output=True,text=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('default: app launch',output.read_text())

if __name__=='__main__':unittest.main()
