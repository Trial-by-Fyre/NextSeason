#!/usr/bin/env python3
"""
analyze-performance-traces.py
NextSeason

Parses xctrace .trace files from profile-performance-suite.sh and emits JSON + markdown.
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
import subprocess
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from xml.etree import ElementTree as ET

NS = {"t": "http://www.apple.com/Instruments/TraceToc"}

# Flows recorded RUNS times each (manifest "runs_per_flow"); the rest have fixed counts.
CORE_FLOWS = (
    "launch",
    "launch-with-data",
    "search",
    "searchEmpty",
    "showDetails",
    "viewWishlist",
    "addToWishlist",
    "removeFromWishlist",
)
FIXED_RUN_COUNTS = {
    "seedWatchlist": 1,
    "network-search": 1,
    "network-showDetails": 1,
    "network-addToWishlist": 1,
    "stressSearchDetailsBack": 1,
    "stressAddRemoveWishlist": 1,
    "stressSearchEmpty": 1,
    "stress-launch-with-data": 10,
}
DEFAULT_RUNS_PER_FLOW = 5

# Evidence a run must provide before its verdict can support beta readiness,
# matching what each kind of run records. Time Profiler flows: the app's
# `flow.<name>` signpost interval, CPU samples, and Allocations, Leaks, and
# Activity Monitor. App Launch: time to first frame, CPU samples, Allocations,
# and Activity Monitor (no Leaks). Network: traffic for the HAR export.
REQUIRED_EVIDENCE = {
    "profile": ("flow timing", "CPU", "memory", "leaks", "hangs", "allocations", "console log"),
    "launch": ("launch timing", "CPU", "memory", "allocations", "console log"),
    "network": ("network HAR", "console log"),
}
# A trace that is missing or cannot be exported provides no evidence at all.
UNUSABLE_TRACE = ("trace", "trace export")

HANG_SCHEMAS = ("potential-hangs", "hang-risks", "hitches")
LEAK_SCHEMAS = ("leaks", "leak")
ALLOCATION_SCHEMAS = ("live-allocations", "all-allocations", "malloc-type-summary")


def flow_kind(flow: str) -> str:
    if flow.startswith("network-"):
        return "network"
    if flow in ("launch", "launch-with-data", "stress-launch-with-data"):
        return "launch"
    return "profile"


def expected_run_counts(runs_per_flow: int) -> dict[str, int]:
    return {**{flow: runs_per_flow for flow in CORE_FLOWS}, **FIXED_RUN_COUNTS}


@dataclass
class FlowMetrics:
    name: str
    runs: int = 0
    expected_runs: int | None = None
    usable_runs: int = 0
    wall_clock_ms: list[float] = field(default_factory=list)
    ttff_ms: list[float] = field(default_factory=list)
    peak_memory_mb: list[float] = field(default_factory=list)
    idle_memory_mb: list[float] = field(default_factory=list)
    baseline_memory_mb: list[float] = field(default_factory=list)
    hangs_over_100ms: list[int] = field(default_factory=list)
    leaks: list[int] = field(default_factory=list)
    top_cpu: Counter = field(default_factory=Counter)
    retained_types: Counter = field(default_factory=Counter)
    network_requests: list[dict[str, Any]] = field(default_factory=list)
    console_issues: list[str] = field(default_factory=list)
    # Evidence names unavailable in at least one run, and readable gap descriptions.
    unavailable: set[str] = field(default_factory=set)
    evidence_gaps: list[str] = field(default_factory=list)

    @property
    def kind(self) -> str:
        return flow_kind(self.name)

    def pass_fail(self) -> str:
        # A measured failure stands even when other evidence is missing.
        if any(l > 0 for l in self.leaks):
            return "FAIL"
        if self.evidence_gaps:
            return "INCOMPLETE"
        if self.retained_types and any(
            t for t in self.retained_types if "ViewModel" in t or "View" in t
        ):
            return "WARN"
        if self.peak_memory_mb and max(self.peak_memory_mb) > 250:
            return "WARN"
        if any(h > 0 for h in self.hangs_over_100ms):
            return "WARN"
        return "PASS"


def export_trace(trace: Path, xpath: str | None = None, har: bool = False) -> str | None:
    """Returns the export, or None when xctrace fails or cannot run."""
    cmd = ["xcrun", "xctrace", "export", "--input", str(trace)]
    if har:
        cmd.append("--har")
    elif xpath:
        cmd.extend(["--xpath", xpath])
    else:
        cmd.append("--toc")
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
    except (subprocess.CalledProcessError, OSError):
        return None


def export_table(trace: Path, schema: str) -> str | None:
    return export_trace(
        trace,
        f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]',
    )


class TraceTables:
    """Exports only tables listed in the trace's table of contents.

    `export` returns None when the table is absent or its export fails, so a
    missing table is never mistaken for an empty one.
    """

    def __init__(self, trace: Path, toc_xml: str):
        self.trace = trace
        self.schemas = set(re.findall(r'<table\b[^>]*\bschema="([^"]+)"', toc_xml))
        try:
            toc = ET.fromstring(toc_xml)
            self.tracks = {
                (track.get("name"), detail.get("name"))
                for track in toc.findall(".//tracks/track")
                for detail in track.findall("./details/detail")
            }
        except ET.ParseError:
            self.tracks = set()

    def export(self, schema: str) -> str | None:
        if schema not in self.schemas:
            return None
        return export_table(self.trace, schema)

    def export_track(self, track: str, detail: str) -> str | None:
        if (track, detail) not in self.tracks:
            return None
        return export_trace(
            self.trace,
            f'/trace-toc/run[@number="1"]/tracks/track[@name="{track}"]/details/detail[@name="{detail}"]',
        )


class TraceXML:
    """Resolve Instruments' shared XML values, including frames and backtraces."""

    def __init__(self, xml: str):
        self.root = ET.fromstring(xml)
        self.definitions = {(e.tag, e.get("id")): e for e in self.root.iter() if e.get("id")}
        schema = self.root.find(".//schema")
        self.columns = {
            col.findtext("mnemonic"): index for index, col in enumerate(schema)
        } if schema is not None else {}

    def resolve(self, element: ET.Element | None) -> ET.Element | None:
        if element is not None and element.get("ref"):
            return self.definitions.get((element.tag, element.get("ref")))
        return element

    def cell(self, row: ET.Element, tag: str) -> ET.Element | None:
        return self.resolve(row.find(tag))

    def field(self, row: ET.Element, name: str) -> ET.Element | None:
        index = self.columns.get(name)
        return self.resolve(row[index]) if index is not None and index < len(row) else None

    @staticmethod
    def number(element: ET.Element | None) -> int | None:
        try:
            return int(element.text) if element is not None else None
        except (TypeError, ValueError):
            return None


def parse_durations(xml: str) -> dict[str, int]:
    return {
        m.group(1): int(m.group(3))
        for m in re.finditer(
            r'<duration id="(\d+)" fmt="([^"]*)"[^>]*>(\d+)</duration>', xml
        )
    }


def parse_ttff(lifecycle_xml: str) -> float | None:
    for row in re.findall(r"<row>(.*?)</row>", lifecycle_xml, re.S):
        if "Initial Frame Rendering" not in row:
            continue
        start = re.search(r"<start-time[^>]*>(\d+)</start-time>", row)
        dur = re.search(r'<duration id="\d+" fmt="[^"]*"[^>]*>(\d+)</duration>', row)
        if start and dur:
            return (int(start.group(1)) + int(dur.group(1))) / 1e6
    return None


def parse_signpost_intervals(signpost_xml: str) -> dict[str, list[float]]:
    """Returns completed Begin/End intervals; repeated table exports are deduplicated."""
    intervals: dict[str, list[float]] = defaultdict(list)
    if not signpost_xml:
        return intervals
    try:
        data = TraceXML(signpost_xml)
    except ET.ParseError:
        return intervals
    starts = {}
    seen = set()
    for row in data.root.findall(".//row"):
        name = data.cell(row, "signpost-name")
        kind = data.cell(row, "event-type")
        time = data.number(data.cell(row, "event-time"))
        identifier = data.number(data.cell(row, "os-signpost-identifier"))
        subsystem = data.cell(row, "subsystem")
        if name is None or kind is None or time is None or subsystem is None:
            continue
        if "NextSeason" not in (subsystem.text or subsystem.get("fmt", "")):
            continue
        key = (name.get("fmt") or name.text, identifier)
        event = (*key, kind.get("fmt"), time)
        if event in seen:
            continue
        seen.add(event)
        if kind.get("fmt") == "Begin":
            starts[key] = time
        elif kind.get("fmt") == "End" and key in starts:
            intervals[key[0]].append((time - starts.pop(key)) / 1e6)
    return intervals


def parse_memory_samples(tables: TraceTables) -> tuple[float | None, float | None, float | None]:
    """Read the physical-footprint column, including inline and referenced values."""
    samples = []
    xml = tables.export("activity-monitor-process-live")
    if xml:
        try:
            data = TraceXML(xml)
            for row in data.root.findall(".//row"):
                process = data.field(row, "process")
                if process is None or not process.get("fmt", "").startswith("NextSeason"):
                    continue
                value = data.number(data.field(row, "memory-physical-footprint"))
                time = data.number(data.field(row, "start"))
                if value is not None and value >= 1024 * 1024 and time is not None:
                    samples.append((time, value / (1024 * 1024)))
        except ET.ParseError:
            pass
    if not samples:
        for schema in ("global-daily-footprint", "physical-footprint", "memory-statistics"):
            xml = tables.export(schema)
            if not xml:
                continue
            try:
                data = TraceXML(xml)
                for row in data.root.findall(".//row"):
                    value = data.number(data.cell(row, "size-in-bytes"))
                    if value is not None:
                        samples.append((len(samples), value / (1024 * 1024)))
            except ET.ParseError:
                continue
    if not samples:
        return None, None, None
    samples.sort()
    values = [value for _, value in samples]
    return values[0], max(values), values[-1]


def parse_roi_duration(signpost_xml: str, signpost_name: str) -> float | None:
    if not signpost_xml or not signpost_name:
        return None
    try:
        data = TraceXML(signpost_xml)
    except ET.ParseError:
        return None
    for row in data.root.findall(".//row"):
        name = data.cell(row, "signpost-name")
        subsystem = data.cell(row, "subsystem")
        if name is None or (name.get("fmt") or name.text) != signpost_name:
            continue
        if subsystem is None or "NextSeason" not in (subsystem.text or subsystem.get("fmt", "")):
            continue
        # Instruments synthesizes a duration up to the end of the recording for
        # open intervals. A missing end process means the flow never finished.
        if "end-process" in data.columns:
            end = data.field(row, "end-process")
            if end is None or end.tag == "sentinel":
                continue
        duration = data.number(data.cell(row, "duration"))
        if duration is not None:
            return duration / 1e6
    return None


def parse_hangs(tables: TraceTables, threshold_ms: float = 100) -> int | None:
    """Counts hangs over the threshold; None when no hang table could be read."""
    count = 0
    measured = False
    for schema in HANG_SCHEMAS:
        xml = tables.export(schema)
        if xml is None:
            continue
        measured = True
        dur_map = parse_durations(xml)
        for row in re.findall(r"<row>(.*?)</row>", xml, re.S):
            if "NextSeason" not in row:
                continue
            ref = re.search(r'<duration ref="(\d+)"/>', row)
            inline = re.search(r'<duration id="\d+" fmt="[^"]*"[^>]*>(\d+)</duration>', row)
            ns = None
            if ref:
                ns = dur_map.get(ref.group(1))
            elif inline:
                ns = int(inline.group(1))
            if ns and ns / 1e6 >= threshold_ms:
                count += 1
    return count if measured else None


def parse_leaks(tables: TraceTables) -> int | None:
    """Read the Leaks detail track as exported by current Instruments versions."""
    exports = [tables.export(schema) for schema in LEAK_SCHEMAS]
    exports.append(tables.export_track("Leaks", "Leaks"))
    for xml in exports:
        if xml is None:
            continue
        try:
            data = TraceXML(xml)
        except ET.ParseError:
            continue
        if data.root.find("node") is not None:
            return len(data.root.findall(".//row"))
    return None


def parse_retained_view_models(tables: TraceTables) -> Counter | None:
    """Live type counts are a retention heuristic, not proof of a memory leak."""
    types = ("SearchViewModel", "ShowDetailViewModel", "WatchlistViewModel", "ShowDetailView", "SearchView")
    xml = tables.export_track("Allocations", "Statistics")
    if xml is not None:
        try:
            data = TraceXML(xml)
            counts = Counter()
            rows = data.root.findall(".//row")
            # An empty/malformed summary is not evidence of zero allocations.
            if not rows or any("count-persistent" not in row.attrib for row in rows):
                return None
            for row in rows:
                category = row.get("category", "")
                for name in types:
                    if category == name or category.endswith("." + name):
                        count = int(row.get("count-persistent"))
                        if count > 0:
                            counts[name] += count
            return counts
        except (ET.ParseError, TypeError, ValueError):
            return None
    counts = Counter()
    measured = False
    for schema in ALLOCATION_SCHEMAS:
        xml = tables.export(schema)
        if xml is None:
            continue
        measured = True
        for name in types:
            counts[name] += len(re.findall(name, xml))
    return +counts if measured else None


@dataclass
class CpuSamples:
    """Usable time-profile samples: those with a weight and a symbol."""

    symbols: Counter
    total: int
    in_window: int


def parse_cpu(
    tables: TraceTables, flow_start_ns: int | None = None, flow_end_ns: int | None = None
) -> CpuSamples | None:
    """Resolve weights, timestamps, frames and backtraces before counting samples."""
    xml = tables.export("time-profile")
    if xml is None:
        return None
    try:
        data = TraceXML(xml)
    except ET.ParseError:
        return None
    symbols = Counter()
    total = in_window = 0
    for row in data.root.findall(".//row"):
        weight = data.number(data.cell(row, "weight"))
        stack = data.cell(row, "tagged-backtrace")
        frames = stack.findall("frame") if stack is not None else row.findall("frame")
        names = []
        for frame in frames:
            frame = data.resolve(frame)
            if frame is not None and frame.get("name"):
                names.append(frame.get("name"))
        if weight is None or weight <= 0 or not names:
            continue
        total += 1
        if flow_start_ns is not None and flow_end_ns is not None:
            time = data.number(data.cell(row, "sample-time"))
            if time is None or not flow_start_ns <= time <= flow_end_ns:
                continue
        in_window += 1
        # Attribute a CPU sample to its leaf, rather than a newly defined caller
        # selected merely because the leaf was exported as a reference.
        symbols[names[0]] += weight / 1e6
    return CpuSamples(symbols=symbols, total=total, in_window=in_window)


def cpu_gap(cpu: CpuSamples | None) -> str | None:
    """Why CPU evidence is unusable, or None when samples fall in the window."""
    if cpu is None or cpu.total == 0:
        return "CPU samples"
    if cpu.in_window == 0:
        return "CPU samples in the analyzed window"
    return None


def har_entries(data: Any) -> list[dict[str, Any]] | None:
    """The HAR's entries, or None unless it has `log.entries` with at least one
    entry and every entry has a `request` with a string `url`.

    A network flow always makes requests, so an empty capture is not evidence.
    """
    log = data.get("log") if isinstance(data, dict) else None
    entries = log.get("entries") if isinstance(log, dict) else None
    if not isinstance(entries, list) or not entries:
        return None
    for entry in entries:
        request = entry.get("request") if isinstance(entry, dict) else None
        if not isinstance(request, dict) or not isinstance(request.get("url"), str):
            return None
    return entries


def parse_network_har(har_path: Path) -> list[dict[str, Any]] | None:
    """TVMaze requests from the HAR export; None when any HAR file is missing,
    unreadable, or not a valid capture."""
    candidates: list[Path] = []
    if har_path.is_dir():
        candidates = sorted(har_path.glob("*.har"))
    elif har_path.exists():
        candidates = [har_path]
    if not candidates:
        return None

    requests: list[dict[str, Any]] = []
    for path in candidates:
        try:
            entries = har_entries(json.loads(path.read_text()))
        except (json.JSONDecodeError, OSError, UnicodeDecodeError):
            return None
        if entries is None:
            return None
        for entry in entries:
            req = entry["request"]
            url = req["url"]
            if "tvmaze" not in url.lower():
                continue
            response = entry.get("response")
            requests.append(
                {
                    "method": req.get("method"),
                    "url": url,
                    "status": response.get("status") if isinstance(response, dict) else None,
                }
            )
    return requests


def parse_console_log(log_path: Path) -> list[str] | None:
    """Issue lines from a console capture; None when the capture is missing or empty.

    An app run always logs under the capture predicate, so an empty file means the
    capture failed rather than that the run was clean.
    """
    try:
        if log_path.stat().st_size == 0:
            return None
    except OSError:
        return None
    issues = []
    patterns = (
        r"error:",
        r"fault:",
        r"warning:",
        r"Swift\.Task",
        r"data race",
        r"Main actor",
        r"runtime warning",
        r"non_fatal",
        r"possible_abrupt",
    )
    for line in log_path.read_text(errors="replace").splitlines():
        lower = line.lower()
        if any(re.search(p, lower) for p in patterns):
            issues.append(line.strip()[:200])
    return issues[:50]


def flow_signpost_name(flow: str) -> str:
    mapping = {
        "launch": "",
        "launch-with-data": "flow.launchWithData",
        "search": "flow.search",
        "searchEmpty": "flow.searchEmpty",
        "showDetails": "flow.showDetails",
        "viewWishlist": "flow.viewWishlist",
        "addToWishlist": "flow.addToWishlist",
        "removeFromWishlist": "flow.removeFromWishlist",
        "stressSearchDetailsBack": "flow.stressSearchDetailsBack",
        "stressAddRemoveWishlist": "flow.stressAddRemoveWishlist",
        "stressSearchEmpty": "flow.stressSearchEmpty",
    }
    return mapping.get(flow, f"flow.{flow}")


def unusable_run(trace: Path, reason: str) -> dict[str, Any]:
    return {"trace": str(trace), "unavailable": [reason]}


def analyze_run(trace: Path, flow: str, log_path: Path | None, har_path: Path | None) -> dict[str, Any]:
    if not trace.exists():
        return unusable_run(trace, "trace")
    toc = export_trace(trace)
    if toc is None:
        return unusable_run(trace, "trace export")
    tables = TraceTables(trace, toc)

    ttff = parse_ttff(tables.export("life-cycle-period") or "")
    signposts = parse_signpost_intervals(tables.export("os-signpost") or "")
    roi_xml = tables.export("OSSignpostIntervals") or tables.export("region-of-interest") or ""
    sp_name = flow_signpost_name(flow)
    wall_ms = parse_roi_duration(roi_xml, sp_name)
    if wall_ms is None and sp_name and sp_name in signposts:
        wall_ms = signposts[sp_name][0]
    elif flow == "launch" and ttff:
        wall_ms = ttff

    baseline, peak, idle = parse_memory_samples(tables)
    hangs = parse_hangs(tables)
    leaks = parse_leaks(tables)
    retained = parse_retained_view_models(tables)

    # TTFF is milliseconds. Launch analysis includes the next 15 seconds;
    # other flow types use the full trace, not an accidental 15 ms launch slice.
    launch_window = flow_kind(flow) == "launch" and ttff is not None
    flow_start = int(ttff * 1e6) if launch_window else None
    flow_end = int((ttff + 15_000) * 1e6) if launch_window else None
    cpu = parse_cpu(tables, flow_start, flow_end)

    network = parse_network_har(har_path) if har_path else None
    console = parse_console_log(log_path) if log_path else None

    near_baseline = None
    if baseline and idle:
        near_baseline = abs(idle - baseline) <= max(5.0, baseline * 0.1)

    available = {
        "flow timing": wall_ms is not None,
        "launch timing": ttff is not None,
        "CPU": cpu_gap(cpu) is None,
        "memory": peak is not None,
        "leaks": leaks is not None,
        "hangs": hangs is not None,
        "allocations": retained is not None,
        "network HAR": network is not None,
        "console log": console is not None,
    }
    # CPU is reported by its specific gap: an empty capture, or samples all
    # outside the analyzed window.
    unavailable = [
        cpu_gap(cpu) if name == "CPU" else name
        for name in REQUIRED_EVIDENCE[flow_kind(flow)]
        if not available[name]
    ]

    return {
        "trace": str(trace),
        "unavailable": unavailable,
        "wall_clock_ms": wall_ms,
        "ttff_ms": ttff,
        "baseline_memory_mb": baseline,
        "peak_memory_mb": peak,
        "idle_memory_mb": idle,
        "memory_near_baseline": near_baseline,
        "hangs_over_100ms": hangs,
        "leaks": leaks,
        "retained_types": dict(retained) if retained is not None else None,
        "top_cpu_ms": cpu.symbols.most_common(10) if cpu is not None else None,
        "cpu_samples": cpu.total if cpu is not None else None,
        "cpu_samples_in_window": cpu.in_window if cpu is not None else None,
        "network_requests": network,
        "console_issues": console,
        "signposts": {k: v for k, v in signposts.items() if v},
    }


def aggregate_flow(name: str, runs: list[dict[str, Any]], expected_runs: int | None) -> FlowMetrics:
    m = FlowMetrics(name=name, runs=len(runs), expected_runs=expected_runs)
    for run in runs:
        unavailable = run.get("unavailable", [])
        if unavailable:
            m.unavailable.update(unavailable)
            m.evidence_gaps.append(
                f"`{Path(run['trace']).name}`: {', '.join(unavailable)} unavailable"
            )
        if not any(reason in unavailable for reason in UNUSABLE_TRACE):
            m.usable_runs += 1
        if run.get("wall_clock_ms") is not None:
            m.wall_clock_ms.append(run["wall_clock_ms"])
        if run.get("ttff_ms") is not None:
            m.ttff_ms.append(run["ttff_ms"])
        if run.get("peak_memory_mb") is not None:
            m.peak_memory_mb.append(run["peak_memory_mb"])
        if run.get("idle_memory_mb") is not None:
            m.idle_memory_mb.append(run["idle_memory_mb"])
        if run.get("baseline_memory_mb") is not None:
            m.baseline_memory_mb.append(run["baseline_memory_mb"])
        if run.get("hangs_over_100ms") is not None:
            m.hangs_over_100ms.append(run["hangs_over_100ms"])
        if run.get("leaks") is not None:
            m.leaks.append(run["leaks"])
        for sym, ms in run.get("top_cpu_ms") or []:
            m.top_cpu[sym] += ms
        for typ, count in (run.get("retained_types") or {}).items():
            m.retained_types[typ] = max(m.retained_types.get(typ, 0), count)
        if run.get("network_requests"):
            m.network_requests.extend(run["network_requests"])
        m.console_issues.extend(run.get("console_issues") or [])

    if expected_runs is None:
        m.evidence_gaps.insert(0, "not an expected suite flow; run count cannot be checked")
    elif m.usable_runs < expected_runs:
        m.evidence_gaps.insert(0, f"{m.usable_runs} of {expected_runs} expected runs usable")
    return m


def readiness(flows: dict[str, FlowMetrics]) -> str:
    verdicts = [m.pass_fail() for m in flows.values()]
    if "FAIL" in verdicts:
        return "not_ready"
    if "INCOMPLETE" in verdicts:
        return "not_established"
    if "WARN" in verdicts:
        return "caution"
    return "safe"


def flows_missing(flows: dict[str, FlowMetrics], evidence: str) -> list[str]:
    return [name for name, m in flows.items() if evidence in m.unavailable]


def fmt_count(values: list[int], recorded: bool) -> str:
    """Sum of measured counts; "—" when unmeasured, "n/a" when not recorded for the flow."""
    if not recorded:
        return "n/a"
    return str(sum(values)) if values else "—"


def avg(values: list[float]) -> float | None:
    return statistics.mean(values) if values else None


def fmt_ms(v: float | None) -> str:
    return f"{v:.0f} ms" if v is not None else "—"


def fmt_mb(v: float | None) -> str:
    return f"{v:.1f} MB" if v is not None else "—"


def render_markdown(session: Path, flows: dict[str, FlowMetrics], raw: dict[str, Any]) -> str:
    lines = [
        "# NextSeason Performance Report",
        "",
        f"Session: `{session.name}`",
        "",
        "## Flow Summary",
        "",
        "| Flow | Pass/Fail | Usable runs | Avg wall-clock | Avg TTFF | Peak mem | Idle mem | Near baseline | Recorded hangs | Leaks |",
        "|---|---|---:|---:|---:|---:|---:|---|---:|---:|",
    ]

    for name, m in flows.items():
        expected = m.expected_runs if m.expected_runs is not None else "?"
        lines.append(
            f"| {name} | **{m.pass_fail()}** | {m.usable_runs}/{expected} | {fmt_ms(avg(m.wall_clock_ms))} | "
            f"{fmt_ms(avg(m.ttff_ms))} | {fmt_mb(max(m.peak_memory_mb) if m.peak_memory_mb else None)} | "
            f"{fmt_mb(avg(m.idle_memory_mb))} | "
            f"{'Yes' if m.baseline_memory_mb and m.idle_memory_mb and avg(m.idle_memory_mb) and avg(m.baseline_memory_mb) and abs(avg(m.idle_memory_mb) - avg(m.baseline_memory_mb)) <= max(5, avg(m.baseline_memory_mb) * 0.1) else '—'} | "
            f"{fmt_count(m.hangs_over_100ms, m.kind != 'network')} | "
            f"{fmt_count(m.leaks, m.kind == 'profile')} |"
        )
    lines.extend([
        "",
        "— = not measured (evidence unavailable). n/a = not recorded by this flow's Instruments template.",
        "Hang counts cover only the threshold configured in Instruments; they do not rule out shorter stalls.",
        "Full-flow wall-clock values include automation waits and sleeps; use phase signposts for user-facing latency.",
    ])

    lines.extend(["", "## Evidence completeness", ""])
    incomplete = {name: m for name, m in flows.items() if m.evidence_gaps}
    if incomplete:
        for name, m in incomplete.items():
            lines.append(f"- **{name}**:")
            for gap in m.evidence_gaps:
                lines.append(f"  - {gap}")
    else:
        lines.append("- All expected runs are present, and every run provided its required evidence.")

    lines.extend(["", "## Live View / ViewModel types (retention heuristic)", ""])
    lines.append("Live objects are expected while a screen is open; these counts alone do not establish a leak.")
    any_retained = False
    for name, m in flows.items():
        if m.retained_types:
            any_retained = True
            lines.append(f"- **{name}**: {dict(m.retained_types)}")
    missing_allocations = flows_missing(flows, "allocations")
    if missing_allocations:
        lines.append(f"- Allocation data unavailable for: {', '.join(missing_allocations)}.")
    if not any_retained:
        scope = "the allocation data available" if missing_allocations else "allocation summaries"
        lines.append(f"- No matching live View/ViewModel types found in {scope}.")

    lines.extend(["", "## Top CPU (aggregated)", ""])
    for name, m in flows.items():
        if not m.top_cpu:
            continue
        lines.append(f"### {name}")
        for sym, ms in m.top_cpu.most_common(6):
            lines.append(f"- {ms:.0f} ms — `{sym[:100]}`")
        lines.append("")

    lines.extend(["", "## Network (duplicate check)", ""])
    missing_har = flows_missing(flows, "network HAR")
    if missing_har:
        lines.append(f"- HAR export unavailable for: {', '.join(missing_har)}.")
        lines.append("")
    for name, m in flows.items():
        if not m.network_requests:
            continue
        urls = [r["url"] for r in m.network_requests]
        dupes = {u: c for u, c in Counter(urls).items() if c > 1}
        lines.append(f"### {name} — {len(urls)} requests")
        if dupes:
            lines.append("- **Duplicate URLs:**")
            for u, c in sorted(dupes.items(), key=lambda x: -x[1])[:8]:
                lines.append(f"  - {c}× {u}")
        else:
            lines.append("- No duplicate URLs in captured HAR.")
        lines.append("")

    lines.extend(["", "## Console warnings / errors", ""])
    all_issues = sorted(set(issue for m in flows.values() for issue in m.console_issues))
    missing_logs = flows_missing(flows, "console log")
    if missing_logs:
        lines.append(f"- Console logs missing or empty for: {', '.join(missing_logs)}.")
    if all_issues:
        for issue in all_issues[:30]:
            lines.append(f"- `{issue}`")
    elif missing_logs:
        lines.append("- None in the logs that were captured.")
    else:
        lines.append("- None captured during profiling runs.")

    lines.extend(["", "## Beta readiness (performance/resources)", ""])
    fails = [n for n, m in flows.items() if m.pass_fail() == "FAIL"]
    incomplete_names = [n for n, m in flows.items() if m.pass_fail() == "INCOMPLETE"]
    warns = [n for n, m in flows.items() if m.pass_fail() == "WARN"]
    verdict = readiness(flows)
    if verdict == "not_ready":
        lines.append(f"- **Not ready** — failures in: {', '.join(fails)}")
        if incomplete_names:
            lines.append(f"- Evidence is also incomplete for: {', '.join(incomplete_names)}")
    elif verdict == "not_established":
        lines.append(
            "- **Readiness not established** — evidence is missing or incomplete for: "
            f"{', '.join(incomplete_names)}. See Evidence completeness."
        )
        if warns:
            lines.append(f"- Warnings in: {', '.join(warns)}")
    elif verdict == "caution":
        lines.append(f"- **Proceed with caution** — warnings in: {', '.join(warns)}")
    else:
        lines.append("- **Safe for beta** from a performance/resource perspective based on this session.")

    lines.extend(["", "## Artifacts", ""])
    lines.append(f"- Raw traces: `{session}/traces/`")
    lines.append(f"- JSON: `{session}/report.json`")
    lines.append("- `.trace` files are gitignored; do not commit.")

    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Analyze NextSeason Instruments traces")
    parser.add_argument("session_dir", type=Path, help="Session directory from profile-performance-suite.sh")
    args = parser.parse_args()

    session = args.session_dir.resolve()
    manifest_path = session / "manifest.json"
    if not manifest_path.exists():
        print(f"error: missing {manifest_path}", file=sys.stderr)
        return 1

    manifest = json.loads(manifest_path.read_text())
    raw_results: dict[str, list[dict[str, Any]]] = defaultdict(list)

    for entry in manifest["runs"]:
        flow = entry["flow"]
        trace = session / entry["trace"]
        log_path = session / entry["log"] if entry.get("log") else None
        har_path = session / entry["har"] if entry.get("har") else None
        if har_path and not har_path.exists():
            alt = session / "har" / flow.replace("network-", "")
            if alt.is_dir():
                har_path = alt
        if not trace.exists():
            print(f"warning: missing trace {trace}", file=sys.stderr)
        raw_results[flow].append(analyze_run(trace, flow, log_path, har_path))

    # Sessions recorded before the suite wrote runs_per_flow used the default.
    runs_per_flow = manifest.get("runs_per_flow", DEFAULT_RUNS_PER_FLOW)
    expected = expected_run_counts(runs_per_flow)
    # Expected flows with no manifest entry still appear, so they count as missing.
    for flow in expected:
        raw_results.setdefault(flow, [])
    flows = {
        name: aggregate_flow(name, runs, expected.get(name)) for name, runs in raw_results.items()
    }

    verdict = readiness(flows)
    if verdict == "not_established":
        print(
            "warning: evidence is incomplete; beta readiness is not established (see report.md)",
            file=sys.stderr,
        )

    report = {
        "session": session.name,
        "readiness": verdict,
        "runs_per_flow": runs_per_flow,
        "flows": {
            name: {
                "pass_fail": m.pass_fail(),
                "runs": m.runs,
                "expected_runs": m.expected_runs,
                "usable_runs": m.usable_runs,
                "evidence_gaps": m.evidence_gaps,
                "avg_wall_clock_ms": avg(m.wall_clock_ms),
                "avg_ttff_ms": avg(m.ttff_ms),
                "peak_memory_mb_max": max(m.peak_memory_mb) if m.peak_memory_mb else None,
                "avg_idle_memory_mb": avg(m.idle_memory_mb),
                "hangs_over_100ms_total": sum(m.hangs_over_100ms) if m.hangs_over_100ms else None,
                "leaks_total": sum(m.leaks) if m.leaks else None,
                "retained_types": dict(m.retained_types),
                "top_cpu_ms": m.top_cpu.most_common(10),
                "network_request_count": len(m.network_requests),
                "console_issue_count": len(set(m.console_issues)),
                "raw_runs": raw_results[name],
            }
            for name, m in flows.items()
        },
    }

    (session / "report.json").write_text(json.dumps(report, indent=2))
    md = render_markdown(session, flows, report)
    (session / "report.md").write_text(md)
    print(md)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
