#!/usr/bin/env python3
"""Compare the same completed stress flow with and without memory instruments."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import runpy
import subprocess
import sys
from xml.etree import ElementTree as ET

FLOW = "stressSearchEmpty"


def outcome_gaps(path: Path, run_id: str) -> list[str]:
    try:
        rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    except (OSError, ValueError):
        return ["outcome file missing or unreadable"]
    if any(not isinstance(row, dict) for row in rows):
        return ["malformed outcome record"]
    events = [row for row in rows if row.get("flow") == FLOW and row.get("run_id") == run_id and "status" in row]
    if not events or events[0].get("status") != "started":
        return ["no start marker for this run (old files cannot prove completion)"]
    failures = [row for row in events if row["status"] in ("failed", "cancelled")]
    if failures:
        return [str(row.get("error") or row["status"]) for row in failures]
    iterations = [row.get("iteration") for row in events if row["status"] == "iteration_completed"]
    gaps = []
    if [row["status"] for row in events] != ["started"] + ["iteration_completed"] * 20 + ["completed"]:
        gaps.append("unexpected or incomplete outcome sequence")
    if not all(type(i) is int for i in iterations) or iterations != list(range(1, 21)):
        gaps.append("expected exactly 20 ordered completed searches")
    if sum(row["status"] == "completed" for row in events) != 1 or events[-1]["status"] != "completed":
        gaps.append("no unique final completion marker")
    return gaps


def bounded_export(trace: Path, xpath: str | None = None, har: bool = False) -> str | None:
    cmd = ["xcrun", "xctrace", "export", "--input", str(trace)]
    cmd += ["--xpath", xpath] if xpath else ["--toc"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=45)
        return result.stdout if result.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def analyze(session: Path) -> dict:
    api = runpy.run_path(str(Path(__file__).with_name("analyze-performance-traces.py")))
    # Bound readback as well as recording; this affects only this imported copy.
    api["analyze_run"].__globals__["export_trace"] = bounded_export
    manifest = json.loads((session / "comparison-manifest.json").read_text())
    results = {}
    for entry in manifest["runs"]:
        gaps = outcome_gaps(session / entry["outcomes"], entry["run_id"])
        trace = session / entry["trace"]
        toc = bounded_export(trace) if trace.exists() else None
        duration = cpu_count = hangs = threshold = None
        if toc is None:
            gaps.append("trace unavailable")
        else:
            tables = api["TraceTables"](trace, toc)
            intervals = tables.export("OSSignpostIntervals") or ""
            duration = api["parse_roi_duration"](intervals, "flow." + FLOW)
            cpu = api["parse_cpu"](tables)
            cpu_count = cpu.total if cpu else None
            if duration is None:
                gaps.append("completed flow interval unavailable")
            if not cpu_count:
                gaps.append("usable CPU samples unavailable")
            xml = tables.export("potential-hangs")
            if xml is None:
                gaps.append("hang evidence unavailable")
            else:
                try:
                    data = api["TraceXML"](xml)
                    if data.root.find("node") is None or data.root.find(".//schema") is None:
                        raise ET.ParseError("missing hang table")
                    hangs = 0
                    for row in data.root.findall(".//row"):
                        process = data.cell(row, "process")
                        duration_ns = data.number(data.cell(row, "duration"))
                        if process is None or duration_ns is None:
                            raise ET.ParseError("unreadable hang row")
                        if process.get("fmt", "").startswith("NextSeason") and duration_ns > 0:
                            hangs += 1
                    toc_root = ET.fromstring(toc)
                    table = toc_root.find('.//table[@schema="potential-hangs"]')
                    threshold = table.get("hangs-threshold") if table is not None else None
                    if threshold is None:
                        gaps.append("hang capture threshold unavailable")
                except ET.ParseError:
                    gaps.append("hang export unreadable")
                    hangs = None
        results[entry["mode"]] = {
            "status": "INCOMPLETE" if gaps else "COMPLETE",
            "gaps": gaps, "flow_ms": duration, "cpu_samples": cpu_count,
            "recorded_hangs": hangs, "capture_threshold_ms": threshold,
        }
    if set(results) == {"time-profiler", "instrumented"} and results["time-profiler"]["capture_threshold_ms"] != results["instrumented"]["capture_threshold_ms"]:
        for result in results.values():
            result["gaps"].append("hang thresholds differ; counts are not comparable")
            result["status"] = "INCOMPLETE"
    complete = set(results) == {"time-profiler", "instrumented"} and all(r["status"] == "COMPLETE" for r in results.values())
    if not complete:
        conclusion = "Comparison incomplete; no performance conclusion is established."
    elif results["time-profiler"]["recorded_hangs"]:
        conclusion = "A hang also occurred without memory instrumentation; further app investigation is needed."
    elif results["instrumented"]["recorded_hangs"]:
        conclusion = "Only the memory-instrumented run recorded a hang. This is consistent with instrumentation contributing in this pair; it is not proof of cause."
    else:
        conclusion = "The earlier hang did not recur in this pair. Its cause remains unresolved."
    report = {"flow": FLOW, "complete": complete, "runs": results, "conclusion": conclusion}
    (session / "comparison.json").write_text(json.dumps(report, indent=2))
    lines = ["# Empty-search stress comparison", "", conclusion, "", "| Capture | Completion | Full flow | Recorded hangs |", "|---|---|---:|---:|"]
    for mode, result in results.items():
        duration = f"{result['flow_ms'] / 1000:.2f} s" if result["flow_ms"] is not None else "—"
        hangs = result["recorded_hangs"] if result["recorded_hangs"] is not None else "—"
        lines.append(f"| {mode} | {result['status']} | {duration} | {hangs} |")
    for mode, result in results.items():
        lines += [f"\n- **{mode}:** {gap}" for gap in result["gaps"]]
    lines += ["", "Each complete run requires 20 ordered searches, current-run completion markers, readable CPU samples, a finished flow interval, and hang evidence.",
              "Hang counts cover each trace's capture threshold (see comparison.json); shorter stalls are not ruled out. One pair is not beta-readiness evidence."]
    (session / "comparison.md").write_text("\n".join(lines) + "\n")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("session", type=Path)
    parser.add_argument("--check-outcomes", metavar="RUN_ID")
    args = parser.parse_args()
    if args.check_outcomes:
        gaps = outcome_gaps(args.session, args.check_outcomes)
        for gap in gaps:
            print("Driver incomplete: " + gap, file=sys.stderr)
        return 1 if gaps else 0
    report = analyze(args.session)
    print(report["conclusion"])
    print("Report: " + str(args.session / "comparison.md"))
    return 0 if report["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
