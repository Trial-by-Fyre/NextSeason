#!/usr/bin/env python3
"""Hermetic checks for device log capture in the performance suite scripts (R17).

Runs copies of the real suite scripts against fake `xcrun` and `log` commands,
in both capture modes, and checks each run's capture is collected or stopped
exactly once, including when a run fails or the script is interrupted, with no
`log stream` process left behind.
"""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]

# Records each call. `record` creates the trace directory; FAKE_HANG_FLOW and
# FAKE_FAIL_FLOW make one flow hang (to interrupt) or fail. Exports always fail.
FAKE_XCRUN = r"""#!/bin/bash
if [[ "$1 $2" == "xctrace record" ]]; then
    args=("$@"); out=""; flow=""
    for ((i = 0; i < ${#args[@]}; i++)); do
        case "${args[i]}" in
            --output) out="${args[i+1]}" ;;
            -ProfileFlow) flow="${args[i+1]}" ;;
        esac
    done
    echo "record ${flow}" >> "${FAKE_CALLS}"
    mkdir -p "${out}"
    [[ -n "${FAKE_HANG_FLOW:-}" && "${flow}" == "${FAKE_HANG_FLOW}" ]] && sleep 30
    [[ -n "${FAKE_FAIL_FLOW:-}" && "${flow}" == "${FAKE_FAIL_FLOW}" ]] && exit 1
    sleep 0.2
    exit 0
fi
[[ "$1 $2" == "xctrace export" ]] && exit 1
exit 0
"""

# `help stream` lists --device-udid only when FAKE_LOG_STREAMS=1. `stream` runs
# until terminated, recording its PID and its termination.
FAKE_LOG = r"""#!/bin/bash
case "$1" in
    help)
        [[ "${FAKE_LOG_STREAMS:-0}" == 1 ]] && echo "  --device-udid <udid>  Stream from a device"
        ;;
    stream)
        trap 'echo "terminated $$" >> "${FAKE_CALLS}"; exit 0' TERM
        echo "stream $$" >> "${FAKE_CALLS}"
        echo "streamed line"
        while true; do sleep 0.1; done
        ;;
    collect)
        if [[ "${FAKE_LOG_FAIL:-0}" == 1 ]]; then
            echo "fake capture access denied" >&2
            exit 1
        fi
        echo "collect $*" >> "${FAKE_CALLS}"
        args=("$@")
        for ((i = 0; i < ${#args[@]}; i++)); do
            [[ "${args[i]}" == --output ]] && mkdir -p "${args[i+1]}"
        done
        exit 0
        ;;
    show)
        echo "collected line"
        ;;
esac
"""

PROFILE_RUNS = 25  # RUNS=1: seed, 8 core flows, 3 network, 3 stress, 10 launches
RESUME_RUNS = 16  # 3 network, 3 stress, 10 launches


class DeviceLogCaptureTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        shutil.copytree(ROOT / "Scripts", self.tmp / "Scripts")
        bin_dir = self.tmp / "bin"
        bin_dir.mkdir()
        for name, body in (("xcrun", FAKE_XCRUN), ("log", FAKE_LOG)):
            (bin_dir / name).write_text(body)
            (bin_dir / name).chmod(0o755)
        (self.tmp / "NextSeason.app").mkdir()
        self.calls = self.tmp / "calls.txt"
        self.calls.touch()
        self.env = {
            **os.environ,
            # The scripts' own `python3` calls use this test's interpreter.
            "PATH": f"{bin_dir}:{Path(sys.executable).parent}:{os.environ['PATH']}",
            "DEVICE_LOG_CMD": str(bin_dir / "log"),
            "DEVICE_LOG_CAPTURE_BACKEND": "native",
            "DEVICE_UDID": "FAKE-UDID",
            "APP_PATH": str(self.tmp / "NextSeason.app"),
            "RUNS": "1",
            "FAKE_CALLS": str(self.calls),
        }
        self.addCleanup(self.kill_leftover_streams)

    # MARK: Helpers

    def command(self, script):
        if script == "profile":
            return ["bash", str(self.tmp / "Scripts/profile-performance-suite.sh")]
        session = self.tmp / "resume-session"
        for sub in ("traces", "logs"):
            (session / sub).mkdir(parents=True, exist_ok=True)
        (session / "manifest.json").write_text('{"runs": []}')
        return ["bash", str(self.tmp / "Scripts/resume-performance-suite.sh"), str(session)]

    def run_script(self, script, streams, **extra_env):
        env = {**self.env, "FAKE_LOG_STREAMS": "1" if streams else "0", **extra_env}
        return subprocess.run(self.command(script), env=env, capture_output=True, text=True, timeout=120)

    def interrupt_script(self, script, streams, hang_flow):
        """Starts the script, then sends Ctrl-C to its process group during `hang_flow`."""
        env = {**self.env, "FAKE_LOG_STREAMS": "1" if streams else "0", "FAKE_HANG_FLOW": hang_flow}
        process = subprocess.Popen(self.command(script), env=env, start_new_session=True,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.monotonic() + 60
        while f"record {hang_flow}" not in self.calls.read_text():
            self.assertIsNone(process.poll(), "the script exited before the hanging flow")
            self.assertLess(time.monotonic(), deadline, "the hanging flow never started")
            time.sleep(0.1)
        time.sleep(0.3)
        os.killpg(process.pid, signal.SIGINT)
        return process.wait(timeout=30)

    def lines(self, prefix):
        return [line for line in self.calls.read_text().splitlines() if line.startswith(prefix)]

    def stream_pids(self):
        return [int(line.split()[1]) for line in self.lines("stream ")]

    def kill_leftover_streams(self):
        for pid in self.stream_pids():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    def assert_every_stream_stopped_once(self, expected_streams):
        pids = self.stream_pids()
        self.assertEqual(len(pids), expected_streams)
        time.sleep(0.3)  # let the fake's `sleep 0.1` children exit
        stopped = [int(line.split()[1]) for line in self.lines("terminated ")]
        self.assertEqual(sorted(stopped), sorted(pids), "each stream is stopped exactly once")
        for pid in pids:
            with self.assertRaises(ProcessLookupError, msg=f"stream {pid} left running"):
                os.kill(pid, 0)

    def log_files(self, script):
        base = self.tmp / (".instruments" if script == "profile" else "resume-session")
        return sorted(base.rglob("logs/*.log"))

    # MARK: Tests

    def test_streaming_capture_is_stopped_once_per_run(self):
        for script, runs in (("profile", PROFILE_RUNS), ("resume", RESUME_RUNS)):
            with self.subTest(script=script):
                self.calls.write_text("")
                result = self.run_script(script, streams=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_every_stream_stopped_once(runs)
                self.assertEqual(self.lines("collect"), [])
                logs = self.log_files(script)
                self.assertEqual(len(logs), runs)
                for log in logs:
                    self.assertIn("streamed line", log.read_text(), log.name)

    def test_fallback_capture_collects_once_per_run(self):
        for script, runs, first_window in (("profile", PROFILE_RUNS, "90s"), ("resume", RESUME_RUNS, "45s")):
            with self.subTest(script=script):
                self.calls.write_text("")
                result = self.run_script(script, streams=False)
                self.assertEqual(result.returncode, 0, result.stderr)
                collects = self.lines("collect")
                self.assertEqual(len(collects), runs)
                self.assertIn("--device-udid FAKE-UDID", collects[0])
                self.assertIn(f"--last {first_window}", collects[0])
                self.assertEqual(self.lines("stream "), [])
                logs = self.log_files(script)
                self.assertEqual(len(logs), runs)
                for log in logs:
                    self.assertIn("collected line", log.read_text(), log.name)

    def test_capture_failure_is_visible_without_fake_log_evidence(self):
        output = self.tmp / "failed-capture.log"
        helper = self.tmp / "Scripts/lib/device-log-capture.sh"
        result = subprocess.run(
            ["bash", "-c", 'set -euo pipefail; source "$1"; device_log_capture_begin FAKE "$2" predicate; device_log_capture_end 2s',
             "capture-test", str(helper), str(output)],
            env={**self.env, "FAKE_LOG_STREAMS": "0", "FAKE_LOG_FAIL": "1"},
            capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("fake capture access denied", result.stderr)
        self.assertIn("console capture failed", result.stderr)
        self.assertEqual(output.read_text(), "")

    def test_failed_run_stops_its_stream(self):
        result = self.run_script("profile", streams=True, FAKE_FAIL_FLOW="search")
        self.assertNotEqual(result.returncode, 0)
        started_runs = len(self.lines("record "))
        self.assert_every_stream_stopped_once(started_runs)

    def test_failed_run_is_not_collected(self):
        result = self.run_script("profile", streams=False, FAKE_FAIL_FLOW="search")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.lines("collect")), len(self.lines("record ")) - 1)

    def test_interrupted_run_stops_its_stream(self):
        for script, hang_flow in (("profile", "search"), ("resume", "stressSearchEmpty")):
            with self.subTest(script=script):
                self.calls.write_text("")
                self.assertEqual(self.interrupt_script(script, True, hang_flow), 130)
                self.assert_every_stream_stopped_once(len(self.lines("record ")))

    def test_interrupted_run_is_not_collected(self):
        self.assertEqual(self.interrupt_script("profile", False, "search"), 130)
        self.assertEqual(len(self.lines("collect")), len(self.lines("record ")) - 1)


if __name__ == "__main__":
    unittest.main()
