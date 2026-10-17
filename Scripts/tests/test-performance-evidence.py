#!/usr/bin/env python3
"""Hermetic checks that incomplete profiling evidence never establishes readiness (R16).

A fake `xcrun` serves trace tables from fixture directories, so no device,
Instruments, or real trace is needed.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
ANALYZER = ROOT / "Scripts/analyze-performance-traces.py"
COMPARISON = ROOT / "Scripts/analyze-uninstrumented-logs.py"

# Serves `xctrace export --toc` from <trace>/toc.xml and `--xpath ...[@schema="X"]`
# from <trace>/tables/X.xml; a missing file is a failed export.
FAKE_XCRUN = r"""#!/bin/bash
input=""; xpath=""; toc=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --input) input="$2"; shift ;;
        --xpath) xpath="$2"; shift ;;
        --toc) toc=1 ;;
    esac
    shift
done
if [[ "${toc}" == 1 ]]; then
    cat "${input}/toc.xml" 2>/dev/null || exit 1
    exit 0
fi
schema="$(sed -n 's/.*@schema="\([^"]*\)".*/\1/p' <<< "${xpath}")"
cat "${input}/tables/${schema}.xml" 2>/dev/null || exit 1
"""

MEMORY = "<row><size-in-bytes>104857600</size-in-bytes></row>"
CPU = ('<row><sample-time fmt="2 s">2000000000</sample-time><weight id="1" fmt="1 ms">1000000</weight>'
       '<frame id="2" name="ProfileFlowRunner.run()"/></row>')
LAUNCH_TIMING = ('<row>Initial Frame Rendering<start-time fmt="00:00.800">800000000</start-time>'
                 '<duration id="1" fmt="200 ms">200000000</duration></row>')
TABLES_BY_KIND = {
    "profile": {"physical-footprint": MEMORY, "leaks": "", "potential-hangs": "",
                "live-allocations": "<row>SomeType</row>", "time-profile": CPU},
    "launch": {"physical-footprint": MEMORY, "live-allocations": "<row>SomeType</row>",
               "time-profile": CPU, "life-cycle-period": LAUNCH_TIMING},
    "network": {},
}


def flow_timing(flow):
    """A region-of-interest row for the app's `flow.<name>` signpost interval."""
    return (f'<row><signpost-name id="1" fmt="flow.{flow}">flow.{flow}</signpost-name>'
            f'<subsystem>NextSeason</subsystem><duration id="2" fmt="5 s">5000000000</duration></row>')
CORE_FLOWS = ("launch", "launch-with-data", "search", "searchEmpty", "showDetails",
              "viewWishlist", "addToWishlist", "removeFromWishlist")
FIXED_FLOWS = {"seedWatchlist": 1, "network-search": 1, "network-showDetails": 1,
               "network-addToWishlist": 1, "stressSearchDetailsBack": 1,
               "stressAddRemoveWishlist": 1, "stressSearchEmpty": 1,
               "stress-launch-with-data": 10}
HAR = {"log": {"entries": [{"request": {"method": "GET", "url": "https://api.tvmaze.com/shows/1"},
                            "response": {"status": 200}}]}}


def kind(flow):
    if flow.startswith("network-"):
        return "network"
    if flow in ("launch", "launch-with-data", "stress-launch-with-data"):
        return "launch"
    return "profile"


class Session:
    """A complete one-run-per-core-flow session that individual tests then damage."""

    def __init__(self, root: Path, runs_per_flow=1, recorded_runs=1):
        self.path = root / "session"
        self.runs = []
        counts = {**{flow: recorded_runs for flow in CORE_FLOWS}, **FIXED_FLOWS}
        for flow, count in counts.items():
            for run in range(1, count + 1):
                self.add_run(flow, run)
        self.manifest = {"runs": self.runs, "runs_per_flow": runs_per_flow}
        self.write_manifest()

    def add_run(self, flow, run):
        name = f"{flow}-run{run}"
        trace = self.path / "traces" / f"{name}.trace"
        tables = dict(TABLES_BY_KIND[kind(flow)])
        if kind(flow) == "profile":
            tables["region-of-interest"] = flow_timing(flow)
        (trace / "tables").mkdir(parents=True)
        toc = "".join(f'<table schema="{schema}"/>' for schema in tables)
        (trace / "toc.xml").write_text(f'<trace-toc><run number="1"><data>{toc}</data></run></trace-toc>')
        for schema, rows in tables.items():
            self.write_table(name, schema, rows)
        log = self.path / "logs" / f"{name}.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text("NextSeason: profile flow finished\n")
        entry = {"flow": flow, "trace": f"traces/{name}.trace", "log": f"logs/{name}.log"}
        if kind(flow) == "network":
            har = self.path / "har" / f"{name}.har"
            har.parent.mkdir(parents=True, exist_ok=True)
            har.write_text(json.dumps(HAR))
            entry["har"] = f"har/{name}.har"
        self.runs.append(entry)

    def trace(self, name):
        return self.path / "traces" / f"{name}.trace"

    def write_table(self, name, schema, rows):
        (self.trace(name) / "tables" / f"{schema}.xml").write_text(
            f"<trace-query-result><node>{rows}</node></trace-query-result>")

    def drop_from_toc(self, name, schema):
        toc = self.trace(name) / "toc.xml"
        toc.write_text(toc.read_text().replace(f'<table schema="{schema}"/>', ""))

    def write_manifest(self):
        (self.path / "manifest.json").write_text(json.dumps(self.manifest))


class AnalyzerEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        bin_dir = self.tmp / "bin"
        bin_dir.mkdir()
        (bin_dir / "xcrun").write_text(FAKE_XCRUN)
        (bin_dir / "xcrun").chmod(0o755)
        self.env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}"}

    def analyze(self, session):
        result = subprocess.run([sys.executable, str(ANALYZER), str(session.path)],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads((session.path / "report.json").read_text())
        return report, (session.path / "report.md").read_text()

    def assert_not_established(self, report, markdown, gap):
        self.assertEqual(report["readiness"], "not_established")
        self.assertNotIn("Safe for beta", markdown)
        self.assertIn("Readiness not established", markdown)
        self.assertIn(gap, markdown)

    def test_complete_session_is_safe(self):
        report, markdown = self.analyze(Session(self.tmp))
        self.assertEqual(report["readiness"], "safe")
        self.assertIn("Safe for beta", markdown)
        self.assertEqual(report["flows"]["search"]["leaks_total"], 0)
        self.assertEqual(report["flows"]["search"]["avg_wall_clock_ms"], 5000)
        self.assertEqual(report["flows"]["launch-with-data"]["avg_ttff_ms"], 1000)
        self.assertTrue(report["flows"]["stress-launch-with-data"]["top_cpu_ms"])

    def test_missing_trace(self):
        session = Session(self.tmp)
        shutil.rmtree(session.trace("search-run1"))
        report, markdown = self.analyze(session)
        self.assert_not_established(report, markdown, "search-run1.trace`: trace unavailable")
        self.assertIn("0 of 1 expected runs usable", markdown)

    def test_failed_trace_export(self):
        session = Session(self.tmp)
        (session.trace("showDetails-run1") / "toc.xml").unlink()
        report, markdown = self.analyze(session)
        self.assert_not_established(report, markdown, "showDetails-run1.trace`: trace export unavailable")

    def test_failed_table_export(self):
        session = Session(self.tmp)
        (session.trace("viewWishlist-run1") / "tables" / "potential-hangs.xml").unlink()
        report, markdown = self.analyze(session)
        self.assert_not_established(report, markdown, "viewWishlist-run1.trace`: hangs unavailable")
        self.assertIsNone(report["flows"]["viewWishlist"]["hangs_over_100ms_total"])

    def test_missing_required_tables(self):
        cases = (("search-run1", "leaks", "leaks"),
                 ("launch-run1", "physical-footprint", "memory"),
                 ("stressSearchEmpty-run1", "live-allocations", "allocations"),
                 ("showDetails-run1", "region-of-interest", "flow timing"),
                 ("seedWatchlist-run1", "time-profile", "CPU samples"),
                 ("launch-with-data-run1", "life-cycle-period", "launch timing"),
                 ("stress-launch-with-data-run3", "time-profile", "CPU samples"))
        for name, schema, evidence in cases:
            with self.subTest(run=name, table=schema):
                session = Session(self.tmp / f"{name}-{schema}")
                session.drop_from_toc(name, schema)
                report, markdown = self.analyze(session)
                self.assert_not_established(report, markdown, f"{name}.trace`: {evidence} unavailable")

    def test_cpu_table_without_usable_samples(self):
        cases = {
            "no rows": "",
            "rows without a symbol": '<row><weight id="1" fmt="1 ms">1000000</weight></row>',
            "rows without a weight": '<row><frame id="2" name="ProfileFlowRunner.run()"/></row>',
            "unresolved weight references":
                '<row><weight ref="9"/><frame id="2" name="ProfileFlowRunner.run()"/></row>',
        }
        for label, rows in cases.items():
            with self.subTest(cpu=label):
                session = Session(self.tmp / label.replace(" ", "-"))
                for run in session.runs:
                    if kind(run["flow"]) != "network":
                        session.write_table(Path(run["trace"]).stem, "time-profile", rows)
                report, markdown = self.analyze(session)
                self.assert_not_established(report, markdown, "search-run1.trace`: CPU samples unavailable")
                self.assertIn("launch-run1.trace`: CPU samples unavailable", markdown)
                self.assertNotIn("analyzed window", markdown)
                self.assertEqual(report["flows"]["search"]["raw_runs"][0]["cpu_samples"], 0)

    def test_resolved_weight_reference_is_a_sample(self):
        session = Session(self.tmp)
        rows = ('<row><weight id="1" fmt="2 ms">2000000</weight><frame id="2" name="First()"/></row>'
                '<row><weight ref="1"/><frame id="3" name="Second()"/></row>')
        session.write_table("search-run1", "time-profile", rows)
        report, _ = self.analyze(session)
        self.assertEqual(report["readiness"], "safe")
        run = report["flows"]["search"]["raw_runs"][0]
        self.assertEqual(run["cpu_samples"], 2)
        self.assertIn(["Second()", 2.0], run["top_cpu_ms"])

    def test_cpu_samples_outside_the_analyzed_window(self):
        session = Session(self.tmp)
        # The launch window is time to first frame (1 s) plus 15 s; this sample is at 99 s.
        late = CPU.replace("2000000000", "99000000000")
        session.write_table("launch-run1", "time-profile", late)
        report, markdown = self.analyze(session)
        self.assert_not_established(
            report, markdown, "launch-run1.trace`: CPU samples in the analyzed window unavailable")
        self.assertNotIn("launch-run1.trace`: CPU samples unavailable", markdown)
        run = report["flows"]["launch"]["raw_runs"][0]
        self.assertEqual((run["cpu_samples"], run["cpu_samples_in_window"]), (1, 0))

    def test_launch_cpu_window_is_fifteen_seconds_not_milliseconds(self):
        session = Session(self.tmp)
        session.write_table("launch-run1", "time-profile", CPU.replace("2000000000", "10000000000"))
        report, _ = self.analyze(session)
        self.assertEqual(report["readiness"], "safe")
        run = report["flows"]["launch"]["raw_runs"][0]
        self.assertEqual(run["cpu_samples_in_window"], 1)

    def test_timing_table_without_the_flow_signpost(self):
        session = Session(self.tmp)
        session.write_table("addToWishlist-run1", "region-of-interest", flow_timing("search"))
        report, markdown = self.analyze(session)
        self.assert_not_established(report, markdown, "addToWishlist-run1.trace`: flow timing unavailable")
        self.assertIsNone(report["flows"]["addToWishlist"]["avg_wall_clock_ms"])

    def test_missing_leaks_table_is_unknown_not_zero(self):
        session = Session(self.tmp)
        session.drop_from_toc("search-run1", "leaks")
        report, markdown = self.analyze(session)
        self.assertIsNone(report["flows"]["search"]["leaks_total"])
        search_row = next(line for line in markdown.splitlines() if line.startswith("| search |"))
        self.assertTrue(search_row.endswith("| — |"), search_row)

    def test_incomplete_run_count(self):
        session = Session(self.tmp, runs_per_flow=2, recorded_runs=1)
        report, markdown = self.analyze(session)
        self.assert_not_established(report, markdown, "1 of 2 expected runs usable")
        self.assertEqual(report["flows"]["search"]["usable_runs"], 1)

    def test_flow_missing_from_manifest(self):
        session = Session(self.tmp)
        session.manifest["runs"] = [r for r in session.runs if r["flow"] != "network-search"]
        session.write_manifest()
        report, markdown = self.analyze(session)
        self.assert_not_established(report, markdown, "0 of 1 expected runs usable")
        self.assertEqual(report["flows"]["network-search"]["pass_fail"], "INCOMPLETE")

    def test_absent_and_empty_logs(self):
        for damage in ("missing", "empty", "not in manifest"):
            with self.subTest(log=damage):
                session = Session(self.tmp / damage.replace(" ", "-"))
                log = session.path / "logs" / "addToWishlist-run1.log"
                if damage == "missing":
                    log.unlink()
                elif damage == "empty":
                    log.write_text("")
                else:
                    del next(r for r in session.runs if r["flow"] == "addToWishlist")["log"]
                    session.write_manifest()
                report, markdown = self.analyze(session)
                self.assert_not_established(
                    report, markdown, "addToWishlist-run1.trace`: console log unavailable")
                self.assertNotIn("None captured during profiling runs", markdown)

    def test_missing_har(self):
        session = Session(self.tmp)
        (session.path / "har" / "network-search-run1.har").unlink()
        report, markdown = self.analyze(session)
        self.assert_not_established(report, markdown, "network-search-run1.trace`: network HAR unavailable")

    def test_invalid_har(self):
        cases = {
            "empty object": "{}",
            "not JSON": "not json",
            "top-level list": "[]",
            "log not an object": '{"log": []}',
            "no entries": '{"log": {}}',
            "entries not a list": '{"log": {"entries": {}}}',
            "empty entries": '{"log": {"entries": []}}',
            "entry not an object": '{"log": {"entries": ["GET /"]}}',
            "request missing": '{"log": {"entries": [{"response": {"status": 200}}]}}',
            "url not a string": '{"log": {"entries": [{"request": {"url": 42}}]}}',
        }
        for label, content in cases.items():
            with self.subTest(har=label):
                session = Session(self.tmp / label.replace(" ", "-"))
                (session.path / "har" / "network-showDetails-run1.har").write_text(content)
                report, markdown = self.analyze(session)
                self.assert_not_established(
                    report, markdown, "network-showDetails-run1.trace`: network HAR unavailable")
                self.assertEqual(report["flows"]["network-showDetails"]["network_request_count"], 0)

    def test_valid_har_counts_requests(self):
        report, _ = self.analyze(Session(self.tmp))
        self.assertEqual(report["flows"]["network-search"]["network_request_count"], 1)

    def test_measured_leak_is_not_ready_despite_other_gaps(self):
        session = Session(self.tmp)
        session.write_table("search-run1", "leaks", "<row>leak</row>")
        shutil.rmtree(session.trace("showDetails-run1"))
        report, markdown = self.analyze(session)
        self.assertEqual(report["readiness"], "not_ready")
        self.assertIn("**Not ready**", markdown)
        self.assertIn("Evidence is also incomplete for: showDetails", markdown)


class UninstrumentedComparisonTests(unittest.TestCase):
    def test_missing_timing_is_unknown_not_fast(self):
        with tempfile.TemporaryDirectory() as tmp:
            session = Path(tmp)
            logs = session / "logs"
            logs.mkdir()
            (logs / "search-run1.jsonl").write_text(
                json.dumps({"flow": "search", "phase": "search.query", "duration_ms": 400}) + "\n")
            (logs / "showDetails-run1.jsonl").write_text("")
            result = subprocess.run(
                [sys.executable, str(COMPARISON), "--session", str(session),
                 "--instruments-report", str(session / "absent.json"),
                 "--flows", "search,showDetails,addToWishlist"],
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = {line.split("|")[1].strip(): line for line in
                    (session / "comparison.md").read_text().splitlines() if line.startswith("| ")}
            self.assertTrue(rows["search"].rstrip().endswith("| No |"), rows["search"])
            for flow in ("showDetails", "addToWishlist"):
                self.assertTrue(rows[flow].rstrip().endswith("| Unknown |"), rows[flow])
            data = json.loads((session / "comparison.json").read_text())
            self.assertEqual(data["showDetails"]["runs_with_timing"], 0)


class RealExportShapeTests(unittest.TestCase):
    """Small fixtures matching XML shapes observed in the October 16 device traces."""

    @classmethod
    def setUpClass(cls):
        import runpy
        cls.analyzer = runpy.run_path(str(ANALYZER))

    def tables(self, xml, track=None):
        class Tables:
            def export(self, schema):
                return xml
            def export_track(self, name, detail):
                return track
        return Tables()

    def test_signpost_events_resolve_refs_and_duplicate_tables(self):
        xml = '''<trace-query-result><node>
          <row><event-time id="1">1000000000</event-time><event-type id="2" fmt="Begin"/>
          <signpost-name id="3" fmt="flow.search"/><subsystem id="4">com.TrialByFyre.NextSeason</subsystem>
          <os-signpost-identifier id="5">42</os-signpost-identifier></row>
          <row><event-time id="6">1620000000</event-time><event-type id="7" fmt="End"/>
          <signpost-name ref="3"/><subsystem ref="4"/><os-signpost-identifier ref="5"/></row>
          <row><event-time ref="1"/><event-type ref="2"/><signpost-name ref="3"/>
          <subsystem ref="4"/><os-signpost-identifier ref="5"/></row>
          <row><event-time ref="6"/><event-type ref="7"/><signpost-name ref="3"/>
          <subsystem ref="4"/><os-signpost-identifier ref="5"/></row>
          </node></trace-query-result>'''
        self.assertEqual(self.analyzer['parse_signpost_intervals'](xml), {'flow.search': [620]})

    def test_completed_interval_required(self):
        prefix = '''<trace-query-result><node><schema>
        <col><mnemonic>start</mnemonic></col><col><mnemonic>duration</mnemonic></col>
        <col><mnemonic>name</mnemonic></col><col><mnemonic>subsystem</mnemonic></col>
        <col><mnemonic>end-process</mnemonic></col></schema><row>
        <start-time>1000000000</start-time><duration>3420000000</duration>
        <signpost-name fmt="flow.search"/><subsystem>com.TrialByFyre.NextSeason</subsystem>'''
        suffix = '</row></node></trace-query-result>'
        parse = self.analyzer['parse_roi_duration']
        self.assertEqual(parse(prefix + '<process fmt="NextSeason"/>' + suffix, 'flow.search'), 3420)
        self.assertIsNone(parse(prefix + '<sentinel/>' + suffix, 'flow.search'))

    def test_cpu_resolves_stack_frame_weight_and_timestamp_references(self):
        xml = '''<trace-query-result><node>
        <row><sample-time id="1">10000000000</sample-time><weight id="2">2000000</weight>
        <tagged-backtrace id="3"><frame id="4" name="Leaf()"/><frame id="5" name="Caller()"/></tagged-backtrace></row>
        <row><sample-time ref="1"/><weight ref="2"/><tagged-backtrace ref="3"/></row>
        <row><sample-time ref="1"/><weight ref="2"/><tagged-backtrace id="6"><frame ref="4"/></tagged-backtrace></row>
        <row><sample-time ref="1"/><weight ref="999"/><tagged-backtrace ref="3"/></row>
        </node></trace-query-result>'''
        cpu = self.analyzer['parse_cpu'](self.tables(xml), 1000000000, 16000000000)
        self.assertEqual((cpu.total, cpu.in_window), (3, 3))
        self.assertEqual(dict(cpu.symbols), {'Leaf()': 6})

    def test_cpu_unknown_timestamp_does_not_prove_window_coverage(self):
        cpu = self.analyzer['parse_cpu'](self.tables(
            '<node><row><weight>1000000</weight><frame name="Leaf()"/></row></node>'), 1, 99)
        self.assertEqual((cpu.total, cpu.in_window), (1, 0))

    def test_memory_reads_physical_footprint_not_first_referenced_size(self):
        xml = '''<trace-query-result><node><schema>
        <col><mnemonic>start</mnemonic></col><col><mnemonic>process</mnemonic></col>
        <col><mnemonic>memory-physical-footprint</mnemonic></col><col><mnemonic>memory-real</mnemonic></col>
        </schema><row><start-time>0</start-time><process id="1" fmt="NextSeason"/>
        <size-in-bytes id="2">20971520</size-in-bytes><size-in-bytes id="3">104857600</size-in-bytes></row>
        <row><start-time>1000000000</start-time><process ref="1"/>
        <size-in-bytes>31457280</size-in-bytes><size-in-bytes ref="3"/></row></node></trace-query-result>'''
        self.assertEqual(self.analyzer['parse_memory_samples'](self.tables(xml)), (20, 30, 30))

    def test_allocation_track_counts_actual_types_not_keypaths(self):
        xml = '''<trace-query-result><node>
        <row category="NextSeason.SearchViewModel" count-persistent="2"/>
        <row category="ReferenceWritableKeyPath&lt;SearchViewModel, String&gt;" count-persistent="15"/>
        <row category="NextSeason.ShowDetailViewModel" count-persistent="0"/>
        </node></trace-query-result>'''
        self.assertEqual(dict(self.analyzer['parse_retained_view_models'](self.tables(None, xml))), {'SearchViewModel': 2})
        self.assertIsNone(self.analyzer['parse_retained_view_models'](self.tables(None, '<trace-query-result><node/></trace-query-result>')))

    def test_leaks_empty_detail_is_zero_but_missing_export_is_unknown(self):
        parse = self.analyzer['parse_leaks']
        self.assertEqual(parse(self.tables(None, '<trace-query-result><node/></trace-query-result>')), 0)
        self.assertEqual(parse(self.tables(None, '<trace-query-result><node><row address="0x1"/></node></trace-query-result>')), 1)
        self.assertIsNone(parse(self.tables(None, None)))
        self.assertIsNone(parse(self.tables(None, 'not XML')))

    def test_track_export_uses_toc_track_detail_path(self):
        from unittest.mock import Mock, patch
        export = Mock(return_value='<trace-query-result><node/></trace-query-result>')
        tables = self.analyzer['TraceTables'](Path('sample.trace'), '''<trace-toc><run number="1"><tracks>
          <track name="Leaks"><details><detail name="Leaks"/></details></track>
          </tracks></run></trace-toc>''')
        globals_ = tables.export_track.__func__.__globals__
        with patch.dict(globals_, {'export_trace': export}):
            self.assertIsNotNone(tables.export_track('Leaks', 'Leaks'))
            self.assertIsNone(tables.export_track('Allocations', 'Statistics'))
        self.assertEqual(export.call_count, 1)
        self.assertIn('/tracks/track[@name="Leaks"]/details/detail[@name="Leaks"]', export.call_args.args[1])


if __name__ == "__main__":
    unittest.main()
