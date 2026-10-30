# NextSeason Scripts

Shell and Python helpers for on-device profiling, crash diagnostics, and asset generation. Most scripts require a connected iPhone and a **Release** build of the app.

Output directories (`.instruments/`) are gitignored.

## Prerequisites

- macOS with Xcode and command-line tools
- iPhone connected via USB, unlocked, and trusted
- For performance scripts: Instruments permissions (the suite installs the app on device before recording)

## Common environment variables

| Variable | Used by | Description |
|---|---|---|
| `DEVICE_UDID` | Most device scripts | xctrace device UDID. Auto-detected when omitted (except where noted). |
| `SKIP_BUILD=1` | Build-aware scripts | Skip the Release build step; app must already exist. |
| `APP_PATH` | Performance suite scripts | Explicit path to `NextSeason.app` instead of auto-resolution. |
| `DEVICE_LOG_CAPTURE_BACKEND=native` | Performance suite scripts | Opt into native device log capture instead of exporting `os_log` from the recorded trace. |
| `USE_SUDO=1` | Native log capture | Retry `log collect` with sudo; attached-device collection requires administrator privileges. |

---

## Performance profiling

### `profile-performance-suite.sh`

Full on-device Instruments battery. Records multiple runs of core app flows, network captures, stress loops, and device console logs, then analyzes everything.

**What it does:**

- Builds and installs a Release build (unless `SKIP_BUILD=1`)
- Runs 5× each core flow: launch, launch-with-data, search, searchEmpty, showDetails, viewWishlist, addToWishlist, removeFromWishlist
- Records network traces for search, showDetails, and addToWishlist
- Runs stress loops (search/details/back, add/remove wishlist, empty search) and 10× launch-with-data
- Writes traces, logs, HAR files, and a manifest under `.instruments/<timestamp>/`
- Calls `analyze-performance-traces.py` to produce `report.md` and `report.json`

**Usage:**

```bash
./Scripts/profile-performance-suite.sh
DEVICE_UDID=... RUNS=5 ./Scripts/profile-performance-suite.sh
SKIP_BUILD=1 ./Scripts/profile-performance-suite.sh
```

**Output:** `.instruments/<timestamp>/` (traces in `traces/`, report at `report.md`)

Each recording has a watchdog: its time limit plus 45 seconds for startup and saving.
A timeout stops the recorder, exits with status 124, and leaves that run out of the manifest.
Ctrl-C also stops the active recorder and cleans up log capture.

To continue a session interrupted during any phase (including core flows):

```bash
SESSION_DIR=.instruments/<timestamp> DEVICE_UDID=... bash ./Scripts/profile-performance-suite.sh
```

The suite uses the session manifest's `runs_per_flow` (default 5 for older sessions).
It skips only exact trace paths recorded in the manifest that still exist, preserving
completed traces and logs. An unlisted partial trace is replaced when retried.

If the Instruments Network recorder crashes, add `SKIP_NETWORK=1` to finish the
other phases. Missing network runs remain incomplete in the report; skipping
them does not establish beta readiness.


---

### `resume-performance-suite.sh`

This older helper resumes only network/stress phases. Prefer the `SESSION_DIR` option above for recovery during core flows or individual repeated launches.

Resumes an interrupted performance suite session. Skips flows already recorded in the session's `manifest.json` or with existing trace files, then finishes network captures, stress loops, and analysis.

**Usage:**

```bash
./Scripts/resume-performance-suite.sh .instruments/20260628-222731
APP_PATH=/path/to/NextSeason.app SKIP_BUILD=1 ./Scripts/resume-performance-suite.sh SESSION_DIR
DEVICE_UDID=... ./Scripts/resume-performance-suite.sh SESSION_DIR
```

---

### `profile-flows.sh`

Lighter-weight Instruments profiling for individual flows. Records one trace per flow (not multiple runs) and writes them directly under `.instruments/`.

**What it does:**

- Cold launch trace
- Traces for searchEmpty, search, showDetails, viewWishlist, addToWishlist, removeFromWishlist
- Seeds the watchlist, then records launch-with-data
- Open traces in Instruments and inspect the **Points of Interest** track for flow signposts

**Usage:**

```bash
./Scripts/profile-flows.sh
DEVICE_UDID=... ./Scripts/profile-flows.sh
SKIP_BUILD=1 ./Scripts/profile-flows.sh
```

**Optional:** `LAUNCH_TIME_LIMIT`, `FLOW_TIME_LIMIT`, `SEED_TIME_LIMIT` (defaults: 20s, 25s, 45s)

**Output:** `.instruments/*.trace`

---

### `run-profile-flows-uninstrumented.sh`

Runs ProfileFlow automation on device **without** Instruments overhead. Pulls timing data from the app container and compares results against an Instruments report.

**What it does:**

- Builds and installs Release (unless `SKIP_BUILD=1`)
- Launches flows via `devicectl` with `DEVICECTL_CHILD_PROFILE_FLOW`
- Pulls `Documents/profile-flow-timing.jsonl` from the app container after each run
- Calls `analyze-uninstrumented-logs.py` to write a comparison report

**Usage:**

```bash
./Scripts/run-profile-flows-uninstrumented.sh
FLOWS=search,showDetails,addToWishlist RUNS=5 ./Scripts/run-profile-flows-uninstrumented.sh
INSTRUMENTS_REPORT=.instruments/<timestamp>/report.json ./Scripts/run-profile-flows-uninstrumented.sh
```

**Environment variables:**

| Variable | Default | Description |
|---|---|---|
| `DEVICE_UDID` | *(hardcoded fallback)* | xctrace destination for build resolution |
| `CORE_DEVICE` | *(hardcoded fallback)* | `devicectl` device UUID for install/launch |
| `RUNS` | `5` | Runs per flow |
| `FLOWS` | `search,showDetails,addToWishlist` | Comma-separated flow names |
| `INSTRUMENTS_REPORT` | `.instruments/20260628-222731/report.json` | Baseline Instruments report for comparison |

**Output:** `.instruments/uninstrumented-<timestamp>/` with `comparison.md` and `comparison.json`

---

### `analyze-performance-traces.py`

Parses `.trace` files from a performance suite session and emits aggregated metrics.

**What it does:**

- Reads `manifest.json` in the session directory
- Exports data from each trace via `xctrace export`
- Aggregates wall-clock time, memory, CPU, hangs, leaks, network, and console issues per flow
- Writes `report.json` and `report.md` with pass/fail/warn verdicts
- Checks evidence completeness: missing traces, failed exports, missing required tables, missing flow timing (the `flow.<name>` signpost, or time to first frame for launches), missing CPU samples, missing or empty console logs, missing or invalid HAR files, and fewer runs than expected (from the manifest's `runs_per_flow`) mark a flow **INCOMPLETE**. Unmeasured values show as “—”, not zero. Any incomplete flow makes beta readiness **not established**, unless a measured failure already makes it **Not ready**
- Reads modern `OSSignpostIntervals` and the Allocations/Leaks track details; resolves shared XML values and rejects unfinished flow intervals
- Uses the physical-footprint memory column and a 15-second post-first-frame CPU window for launch flows; other flows use all CPU samples
- Live View/ViewModel allocation counts are a retention heuristic, not proof of a leak; console capture failures are printed instead of hidden

**Usage:**

```bash
python3 Scripts/analyze-performance-traces.py .instruments/<timestamp>
```

Normally invoked automatically by `profile-performance-suite.sh` and `resume-performance-suite.sh`.

---

### `analyze-uninstrumented-logs.py`

Compares uninstrumented ProfileFlow timing logs against an Instruments baseline report.

**Usage:**

```bash
python3 Scripts/analyze-uninstrumented-logs.py \
  --session .instruments/uninstrumented-<timestamp> \
  --instruments-report .instruments/<timestamp>/report.json \
  --flows search,showDetails,addToWishlist
```

Normally invoked automatically by `run-profile-flows-uninstrumented.sh`. A flow with no user-facing timing is reported as “Unknown” under “Feels slow?”.

---

## Show ID mapping

### `generate-tvdb-tvmaze-show-id-mapping-db.py`

Walks TVMaze’s paginated show index and regenerates the bundled
`NextSeason/Resources/ShowIDMapping/tvdb_tvmaze_show_id_mapping.sqlite` mapping
(TheTVDB id → TVMaze id, title, and medium poster URL). Schema version 2.

**When to run:** manually before an App Store release (or whenever the catalog
should be refreshed in source control). Not hooked into normal Xcode builds.
Safe to invoke from future CI. On-device copies with an older schema are
replaced from this bundled snapshot on launch.

**When to run:** manually before an App Store release (or whenever the catalog
should be refreshed in source control). Not hooked into normal Xcode builds.
Safe to invoke from future CI.

**Usage:**

```bash
./Scripts/generate-tvdb-tvmaze-show-id-mapping-db.py
./Scripts/generate-tvdb-tvmaze-show-id-mapping-db.py --output /tmp/out.sqlite
```

Respects TVMaze rate limits with polite pacing. The generated file is
TVMaze-derived (CC BY-SA); see `NextSeason/Resources/ShowIDMapping/ATTRIBUTION.md`.

---

## Diagnostics

### `verify-crash-reporting.sh`

Checks Release build settings required for symbolicated crash logs in Xcode Organizer (TestFlight and on-device builds).

**What it does:**

- Verifies `DEBUG_INFORMATION_FORMAT=dwarf-with-dsym` and `COPY_PHASE_STRIP=NO` for Release
- Prints bundle ID, version, and a manual Organizer checklist

**Usage:**

```bash
./Scripts/verify-crash-reporting.sh
```

Exits with code 1 if any automated check fails.

---

## Nightly tests

### `run-nightly-tests.sh`

Runs the complete unit and UI suite (the `SerialTesting` plan) on each supported iOS simulator, one version at a time, against the latest commit of the branch checked out in your working copy. Scheduled nightly by a LaunchAgent; can also be run by hand.

**What it does:**

- Reads which branch your working copy has checked out when the run starts and tests that branch's latest commit. Uncommitted changes are never included, and nothing is fetched. If the working copy is in a detached HEAD state (no branch, for example mid-rebase), the run is skipped and the summary says why. The commit is checked out, detached, in its own Git worktree at `~/Library/Developer/NightlyTests/NextSeason/checkout`. Your working copy, its branch, and its uncommitted changes are never touched; only `git worktree list` shows the extra checkout.
- Copies the untracked `Config/Secrets.xcconfig` from the main working copy into that checkout (a unit test checks the Aptabase key).
- Builds once with `build-for-testing` into a dedicated DerivedData folder, then runs `test-without-building` for iOS 18.6 (iPhone 16 Pro), 26.5 (iPhone 17 Pro), and 27.0 (iPhone 18 Pro Max). Parallel testing stays as the test plan sets it (serial).
- Uses dedicated simulators named `NextSeason Nightly <device> iOS <version>`, created on first use. Each is erased before its run and shut down afterwards. Your other simulators, Xcode's DerivedData, and Xcode's selected run destination are not changed.
- Sets `DEVELOPER_DIR` explicitly (default `/Applications/Xcode-27.0.0.app`): `xcode-select` on this Mac points at the Command Line Tools, which cannot run simulator tests. Uses `/usr/bin/python3`, because the first `python3` on this Mac's `PATH` is an x86_64 build that does not run.
- Keeps the Mac from idle-sleeping while it runs (`caffeinate -i`, no settings change), allows one run at a time (a lock left by an interrupted run is detected and cleared), and stops any build or OS step that exceeds 90 minutes.
- Writes a summary and keeps the newest 14 runs.

**Usage:**

```bash
./Scripts/run-nightly-tests.sh                          # full run of the checked-out branch
./Scripts/run-nightly-tests.sh --ref improving-test-performance
./Scripts/run-nightly-tests.sh --os 27.0 --only-testing "NextSeasonUITests/NavigationUITests/testLaunchShowsSearchTab()"
```

A full run is estimated at 25–40 minutes (about 8 minutes per iOS version on iOS 18.6, plus the build). In the October 29 smoke run (3 tests per iOS version), a build from scratch took 42 seconds and each iOS version about 1.5–2 minutes, mostly simulator boot. `--os` and `--only-testing` can be repeated; a summary of a subset says it was not a full run.

**Output:** `~/Library/Developer/NightlyTests/NextSeason/`

- `latest/summary.md`: the report for the most recent run (also printed at the end of the run)
- `history.log`: one line per run, for example `2026-10-30 02:00:04  FAILED  improving-test-performance  d7c88a3bf4  18.6:failed(1)  26.5:ok  27.0:ok  2026-10-30_020004`
- `runs/<timestamp>/`: `summary.md`, `summary.json`, `run.log`, `build.log`, `run.env` (revision, Xcode, macOS), and one `ios-<version>.xcresult` and `ios-<version>.log` per iOS version. Open a result bundle in Xcode to investigate a failure.

**Reading the summary:** the first line answers whether the run passed. It also gives the revision (full commit hash, branch, and subject), the Xcode and macOS versions, and each iOS version's runtime build, elapsed time, pass/fail/skip counts, and whether the screen was locked when that version's tests started. Each failing test is marked one of two ways:

- *Listed known failure*: its test identifier, iOS version, and device match a line in `Scripts/nightly-known-failures.txt`. The match is by name and environment only, so confirm the message matches the symptom recorded in `Documentation/Reviews/Known-Test-Failures.md`.
- *Possibly new*: everything else. Each failure also says whether it failed in the previous run. That is context, not proof it is known.

Add a line to `nightly-known-failures.txt` only for a failure confirmed and recorded in `Known-Test-Failures.md`, and remove it when the issue is fixed. The runner reads the file from the main working copy, so the current list applies whichever revision is tested. The summary also notes a listed failure that did not fail.

**Exit status:** 0 passed (or a run skipped for a late start or detached HEAD), 1 test or build failure, 2 setup error, 75 another run still holding the lock, 130/143 interrupted.

**Configuration (environment variables):**

| Variable | Default | Description |
|---|---|---|
| `NIGHTLY_REF` | *(checked-out branch)* | Test this branch, tag, or commit instead (`--ref` overrides) |
| `DEVELOPER_DIR` | `/Applications/Xcode-27.0.0.app/Contents/Developer` | Xcode used to build and test |
| `DESTINATIONS` | `18.6\|iPhone 16 Pro;26.5\|iPhone 17 Pro;27.0\|iPhone 18 Pro Max` | iOS versions and devices to test |
| `NIGHTLY_ROOT` | `~/Library/Developer/NightlyTests/NextSeason` | Checkout, DerivedData, and results |
| `KEEP_RUNS` | `14` | Run folders kept (each is about 60 MB) |
| `STEP_TIMEOUT_SECONDS` | `5400` | Limit for the build and for each iOS version |
| `LATE_START_WINDOW` | `02:00-04:00` | Times in which a scheduled run may start (may span midnight) |
| `NIGHTLY_CLEAN_BUILD=1` | off | Delete the nightly DerivedData before building |

### `install-nightly-tests.sh`

Installs the LaunchAgent `com.trialbyfyre.nextseason.nightly-tests` for the current user, scheduled daily at 2:00 AM. A scheduled run may start until 4:00 AM; changing the time moves this two-hour window with it. It copies `run-nightly-tests.sh` and `nightly-test-report.py` into `~/Library/Developer/NightlyTests/NextSeason/bin` and runs those copies, so the job keeps working when this working copy switches branches. **Re-run the installer after changing either script.** Installing does not need administrator rights and changes no power settings.

```bash
./Scripts/install-nightly-tests.sh --print        # show the LaunchAgent plist; installs nothing
./Scripts/install-nightly-tests.sh                # install, or update after script changes
NIGHTLY_HOUR=3 NIGHTLY_MINUTE=30 ./Scripts/install-nightly-tests.sh   # change the schedule
./Scripts/install-nightly-tests.sh --uninstall    # stop scheduling; results are kept
./Scripts/install-nightly-tests.sh --uninstall --remove-simulators
```

`DEVELOPER_DIR`, `LATE_START_WINDOW`, and `NIGHTLY_REF` (to pin one branch instead of following the checked-out one) can also be set when installing. Check that it is loaded with `launchctl print gui/$(id -u)/com.trialbyfyre.nextseason.nightly-tests`.

**Running manually:** run `./Scripts/run-nightly-tests.sh` (above). `launchctl kickstart gui/$(id -u)/com.trialbyfyre.nextseason.nightly-tests` starts the installed job immediately, but as a scheduled run, so it is skipped outside the late-start window.

**Sleep, log-out, and scheduling behavior:**

- The job runs only while you are logged in: UI tests need your GUI session, and the agent is limited to it. If you are logged out at 2:00 AM, that night is not run.
- **Not yet verified:** whether UI tests pass with the screen locked. The smoke test ran unlocked. Each summary records the screen state per iOS version; the first run that shows `screen at start: locked` with passing UI tests settles it. If UI tests fail only on locked runs, the Mac must stay unlocked overnight.
- If the Mac is asleep at 2:00 AM, launchd starts the job when it next wakes, and several missed nights coalesce into one run (see `man launchd.plist`, `StartCalendarInterval`). A scheduled start after 4:00 AM is recorded as skipped rather than loading the Mac during the day. A Mac that is shut down does not run the job.
- To run reliably at 2:00 AM while the Mac sleeps, schedule a wake shortly before it, for example `sudo pmset repeat wake MTWRFSU 01:55:00` (needs administrator rights; undo with `sudo pmset repeat cancel`). The scripts never change power settings.
- Once started, the run keeps the Mac awake until it finishes. Closing a laptop lid still sleeps it; the run continues after wake, and a step past its time limit is stopped.

**Troubleshooting:**

- *No new run in `history.log`:* the agent is not loaded (`launchctl print ...` above), you were logged out, or the Mac was off. Check `~/Library/Developer/NightlyTests/NextSeason/logs/launchd.log` for errors that happened before the run started.
- *SKIPPED, detached HEAD:* the working copy had no branch checked out when the run started (for example during a rebase or after checking out a commit). Check out a branch.
- *SKIPPED, another run is still running:* a previous run is still going or hung. If it is no longer running, the next run clears its stale lock automatically.
- *ERROR: iOS X simulator runtime is not installed:* install the runtime (Xcode › Settings › Components), or change `DESTINATIONS` and reinstall.
- *ERROR: DEVELOPER_DIR not found:* Xcode moved or was renamed; reinstall with the new `DEVELOPER_DIR`.
- *BUILD FAILED:* read `build.log` in the run folder. If the error suggests stale build state, run once with `NIGHTLY_CLEAN_BUILD=1`.
- *A failure that does not reproduce in Xcode:* compare devices and iOS versions; the nightly simulators are freshly erased each run. Use `--os` and `--only-testing` to rerun one test the same way.
- *The checkout is in a bad state:* delete `~/Library/Developer/NightlyTests/NextSeason/checkout`; the next run re-creates the worktree.

### `nightly-test-report.py`

Writes `summary.md`, `summary.json`, and the `history.log` line for one run folder. Normally invoked by `run-nightly-tests.sh`; it can be re-run by hand: `/usr/bin/python3 Scripts/nightly-test-report.py <run folder> --runs-dir <runs> --known Scripts/nightly-known-failures.txt`.

---

## Shared libraries (`lib/`)

These are sourced by other scripts, not run directly.

| File | Purpose |
|---|---|
| `lib/performance-suite-common.sh` | Device detection, app path resolution, build, and install helpers for performance scripts |
| `lib/device-log-capture.sh` | Device console capture: suite scripts default to exporting `os_log` from the saved trace; native mode streams or polls `log collect`. Call begin/end in the script's own shell, not in `$(...)`; the cleanup trap stops a stream on failure or Ctrl-C |

## Script tests (`tests/`)

Hermetic Python `unittest` checks using fake commands; no device needed. Run each with `python3 Scripts/tests/<file>.py`.

| File | Covers |
|---|---|
| `tests/test-complimentary-plus-build.py` | Complimentary Plus build-configuration guard |
| `tests/test-performance-evidence.py` | Incomplete profiling evidence never establishes readiness |
| `tests/test-device-log-capture.py` | Both suite scripts' log capture (stream and fallback), including failure and interruption |
| `tests/test-nightly-tests.py` | Nightly runner and report: branch selection and isolation, detached HEAD, failure classification, build failure, locking, start window, timeouts, interruption, and pruning (run with `/usr/bin/python3`) |

### Short stress-driver comparison

After repairing the repeated-search driver, compare two fresh 60-second captures of the same 20 empty searches: Time Profiler alone, then Time Profiler with Allocations, Leaks, and Activity Monitor. Keep the physical phone connected, unlocked, and its screen on throughout. From the repository root:

```bash
DEVELOPER_DIR="/Applications/Xcode-27.0.0.app/Contents/Developer" \
DEVICE_UDID=00008160-001E1DE204C1400A \
bash ./Scripts/profile-stress-comparison.sh
```

The script builds and installs the current Profile app, uses `/usr/bin/python3`, and writes a new `.instruments/stress-comparison-*` folder. Each capture gets a unique run identifier. The copied app outcomes must contain an ordered start, all 20 successful iterations, and one completion for that identifier; a failure stops the second capture. Both trace exports must also contain completed flow timing, usable CPU samples, and readable hang evidence with matching capture thresholds. Read `comparison.md` in the session folder. A missing measurement makes the comparison incomplete. This comparison neither replaces the full suite nor establishes beta readiness.

### Capture repairs verified October 16

The suite and resume scripts now add `os_log` to their recordings and export readable app-process events into each run’s console file. This avoids administrator-only attached-device `log collect`. A missing, unreadable, or empty app log remains missing evidence; exporter diagnostics go only to stderr. Native capture remains available with `DEVICE_LOG_CAPTURE_BACKEND=native`.

Network runs now combine Time Profiler with HTTP Traffic instead of the Network template: the latter crashed in Apple’s `NetworkConnectionStatsModeling`. A physical-phone trial of the replacement finished and exported 47 HTTP requests. `export-performance-evidence.py` exports HAR into a temporary directory, as required by this Xcode, validates the generated files, and merges their entries into the run’s expected `.har` artifact. HAR files can contain credentials and response data; keep these local, gitignored artifacts out of shared reports.

Timed captures pass `-ProfileRequireSignposts`; the driver waits up to 10 seconds for signpost recording before beginning the flow. This repaired the missing Begin event in a second paired physical run. Uninstrumented and Network-only callers need not request this timing handshake. The completed pair recorded zero hangs with Time Profiler alone and one 1.20 s hang with the memory instruments, at the same 250 ms threshold. This supports an instrumentation contribution, without establishing cause or beta readiness.
