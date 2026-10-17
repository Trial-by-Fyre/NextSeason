#!/usr/bin/env python3
"""
analyze-uninstrumented-logs.py
NextSeason

Parses OSLog captures from run-profile-flows-uninstrumented.sh and compares
against Instruments report.json averages.
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
from pathlib import Path

TIMING_RE = re.compile(
    r'"flow"\s*:\s*"(\w+)"(?:.*?"phase"\s*:\s*"(\S+)")?.*?"duration_ms"\s*:\s*(\d+)'
)
HANG_RE = re.compile(r"(Hang Risk|Severe Hang Risk|hang risk|potential hang)", re.I)
RUNTIME_ISSUE_RE = re.compile(r"com\.apple\.runtime-issues")
OSLOG_TIMING_RE = re.compile(
    r"profile_flow_timing flow=(\w+) (?:phase=(\S+) )?duration_ms=(\d+)"
)


def parse_log(path: Path) -> dict:
    timings: dict[str, list[int]] = {}
    phases: dict[str, list[int]] = {}
    hangs: list[str] = []

    if not path.exists():
        return {"timings": timings, "phases": phases, "hangs": hangs}

    text = path.read_text(errors="replace")
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
            flow = obj.get("flow", "")
            ms = int(obj.get("duration_ms", 0))
            phase = obj.get("phase")
            if phase:
                phases.setdefault(f"{flow}.{phase}", []).append(ms)
            else:
                timings.setdefault(flow, []).append(ms)
        except json.JSONDecodeError:
            m = TIMING_RE.search(line) or OSLOG_TIMING_RE.search(line)
            if m:
                flow, phase, ms = m.group(1), m.group(2), int(m.group(3))
                if phase:
                    phases.setdefault(f"{flow}.{phase}", []).append(ms)
                else:
                    timings.setdefault(flow, []).append(ms)
        if HANG_RE.search(line) or RUNTIME_ISSUE_RE.search(line):
            if "NextSeason" in line or "runtime-issues" in line:
                hangs.append(line.strip()[:180])

    return {"timings": timings, "phases": phases, "hangs": hangs}


def avg(values: list[int]) -> float | None:
    return statistics.mean(values) if values else None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--session", required=True)
    parser.add_argument("--instruments-report", required=True)
    parser.add_argument("--flows", default="search,showDetails,addToWishlist")
    args = parser.parse_args()

    session = Path(args.session)
    log_dir = session / "logs"
    flows = [f.strip() for f in args.flows.split(",") if f.strip()]

    instruments = {}
    inst_path = Path(args.instruments_report)
    if inst_path.exists():
        data = json.loads(inst_path.read_text())
        for name, flow in data.get("flows", {}).items():
            instruments[name] = flow.get("avg_wall_clock_ms")

    # Instruments used flow keys like search, showDetails, addToWishlist
    inst_phase = {
        "search": instruments.get("search"),
        "showDetails": instruments.get("showDetails"),
        "addToWishlist": instruments.get("addToWishlist"),
    }

    results: dict[str, dict] = {}
    all_hangs: list[str] = []

    user_phase_key = {
        "search": "search.search.query",
        "showDetails": "showDetails.showDetails.load",
        "addToWishlist": "addToWishlist.watchlist.add",
    }

    # Hang results only mean something if at least one capture had content.
    any_log_content = False
    for flow in flows:
        run_timings: list[int] = []
        run_phases: dict[str, list[int]] = {}
        runs_with_timing = 0
        for log in sorted(log_dir.glob(f"{flow}-run*.jsonl")) + sorted(log_dir.glob(f"{flow}-run*.log")):
            if log.stat().st_size > 0:
                any_log_content = True
            parsed = parse_log(log)
            if flow in parsed["timings"]:
                run_timings.extend(parsed["timings"][flow])
            has_timing = flow in parsed["timings"]
            for key, values in parsed["phases"].items():
                if key.startswith(flow):
                    run_phases.setdefault(key, []).extend(values)
                    has_timing = True
            if has_timing:
                runs_with_timing += 1
            all_hangs.extend(parsed["hangs"])

        preferred = user_phase_key.get(flow)
        user_ms = avg(run_phases.get(preferred, [])) if preferred else None
        if user_ms is None:
            for pk, values in run_phases.items():
                if pk.startswith(f"{flow}."):
                    user_ms = avg(values)
                    break

        results[flow] = {
            "runs": len(list(log_dir.glob(f"{flow}-run*.jsonl"))) + len(list(log_dir.glob(f"{flow}-run*.log"))),
            "runs_with_timing": runs_with_timing,
            "flow_avg_ms": avg(run_timings),
            "user_phase_avg_ms": user_ms,
            "flow_range_ms": (
                f"{min(run_timings):.0f}-{max(run_timings):.0f}" if run_timings else None
            ),
            "instruments_avg_ms": inst_phase.get(flow),
        }

    lines = [
        "# Uninstrumented vs Instruments Comparison",
        "",
        f"Session: `{session.name}`",
        "",
        "| Flow | Runs with timing | User-facing phase (OSLog) | Full flow (OSLog) | Instruments avg | Delta | Feels slow? |",
        "|---|---:|---:|---:|---:|---:|---|",
    ]

    for flow in flows:
        r = results[flow]
        user = r["user_phase_avg_ms"]
        full = r["flow_avg_ms"]
        inst = r["instruments_avg_ms"]
        delta = (inst - user) if (inst is not None and user is not None) else None
        # Without a user-facing timing there is no basis for "No".
        if user is None:
            slow = "Unknown"
        elif user > 3500:
            slow = "Yes"
        elif user > 2000:
            slow = "Borderline"
        else:
            slow = "No"
        user_s = f"{user:.0f} ms" if user is not None else "—"
        full_s = f"{full:.0f} ms ({r['flow_range_ms']})" if full is not None else "—"
        inst_s = f"{inst:.0f} ms" if inst is not None else "—"
        delta_s = f"{delta:+.0f} ms (Instruments overhead/wait)" if delta is not None else "—"
        lines.append(
            f"| {flow} | {r['runs_with_timing']}/{r['runs']} | {user_s} | {full_s} | {inst_s} | {delta_s} | {slow} |"
        )

    lines.extend(["", "## Main-thread hangs outside Instruments", ""])
    unique_hangs = sorted(set(all_hangs))
    if unique_hangs:
        for h in unique_hangs[:20]:
            lines.append(f"- `{h}`")
    elif not any_log_content:
        lines.append("- **Unknown** — no log content was captured during uninstrumented runs.")
    else:
        lines.append("- **None** — no Hang Risk / runtime-issues entries in OSLog during uninstrumented runs.")

    lines.extend(["", "## Interpretation", ""])
    lines.append(
        "- **User-facing phase** times use event-driven waits (search results visible, detail loaded) "
        "instead of the fixed 5 s sleep used under Instruments."
    )
    lines.append(
        "- A large positive delta vs Instruments means the prior profile was dominated by "
        "automation padding and/or Instruments attach overhead, not app slowness."
    )

    report = "\n".join(lines) + "\n"
    (session / "comparison.md").write_text(report)
    (session / "comparison.json").write_text(json.dumps(results, indent=2))
    print(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
