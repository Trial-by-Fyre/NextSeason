#!/usr/bin/env python3
"""Writes summary.md and summary.json for one nightly test run.

Reads the run directory written by run-nightly-tests.sh (run.env, steps.tsv,
and one .xcresult bundle per iOS version) and appends one line to history.log.

A failure is "listed known" only when its exact test identifier, iOS version,
and device match an entry in the owner-maintained known-failures file; every
other failure is "possibly new". Whether a test also failed in the previous
completed run is shown as context, never as a classification.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys

MESSAGE_LIMIT = 400


def read_env(path):
    env = {}
    if path.exists():
        for line in path.read_text().splitlines():
            key, sep, value = line.partition('=')
            if sep:
                env.setdefault(key, []).append(value)
    return env


def first(env, key, default=''):
    return env.get(key, [default])[-1]


def read_steps(path):
    steps = []
    if path.exists():
        for line in path.read_text().splitlines():
            fields = line.split('\t')
            if len(fields) != 9:
                continue
            kind, os_version, device, udid, runtime, start, end, code, state = fields
            steps.append({
                'kind': kind, 'os': os_version, 'device': device, 'udid': udid,
                'runtime_build': runtime, 'start': int(start), 'end': int(end),
                'exit': int(code), 'state': state,
            })
    return steps


def read_known(path):
    """Parses `test id | iOS version or * | device or * | reference` lines."""
    entries = []
    if path and Path(path).exists():
        for line in Path(path).read_text().splitlines():
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = [part.strip() for part in line.split('|')]
            if len(parts) >= 4:
                entries.append({'test': parts[0], 'os': parts[1], 'device': parts[2],
                                'reference': ' | '.join(parts[3:])})
    return entries


def match_known(known, test, os_version, device):
    for entry in known:
        if (entry['test'] == test and entry['os'] in ('*', os_version)
                and entry['device'] in ('*', device)):
            return entry
    return None


def xcresult_summary(bundle):
    if not bundle.exists():
        return None
    result = subprocess.run(
        ['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(bundle)],
        capture_output=True, text=True)
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except ValueError:
        return None


def duration(seconds):
    seconds = max(0, int(seconds))
    hours, rest = divmod(seconds, 3600)
    minutes, secs = divmod(rest, 60)
    if hours:
        return '%dh %02dm %02ds' % (hours, minutes, secs)
    return '%dm %02ds' % (minutes, secs)


def clock(epoch):
    return datetime.datetime.fromtimestamp(epoch).strftime('%Y-%m-%d %H:%M:%S')


def previous_run(runs_dir, run_id):
    """Most recent earlier run that executed tests, as (run_id, summary dict)."""
    if not runs_dir or not Path(runs_dir).is_dir():
        return None, None
    for name in sorted(os.listdir(runs_dir), reverse=True):
        if name >= run_id:
            continue
        path = Path(runs_dir) / name / 'summary.json'
        try:
            data = json.loads(path.read_text())
        except (OSError, ValueError):
            continue
        if data.get('platforms'):
            return name, data
    return None, None


def build_report(run_dir, known, runs_dir):
    env = read_env(run_dir / 'run.env')
    steps = read_steps(run_dir / 'steps.tsv')
    run_id = first(env, 'run_id', run_dir.name)
    prev_id, prev = previous_run(runs_dir, run_id)
    prev_failures = {}
    if prev:
        for platform in prev['platforms']:
            prev_failures[platform['os']] = {f['test'] for f in platform['failures']}

    report = {
        'run_id': run_id,
        'ref': first(env, 'ref'),
        'branch': first(env, 'branch'),
        'sha': first(env, 'sha'),
        'subject': first(env, 'subject'),
        'commit_date': first(env, 'commit_date'),
        'xcode': first(env, 'xcode').strip(),
        'macos': first(env, 'macos'),
        'scheduled': first(env, 'scheduled') == '1',
        'only_testing': first(env, 'only_testing'),
        'started_at': int(first(env, 'started_at', '0') or 0),
        'finished_at': int(first(env, 'finished_at', '0') or 0),
        'exit_status': int(first(env, 'exit_status', '0') or 0),
        'warnings': env.get('warning', []),
        'previous_run': prev_id,
        'platforms': [],
        'build': None,
    }

    for step in steps:
        if step['kind'] == 'build':
            report['build'] = {'state': step['state'], 'exit': step['exit'],
                               'elapsed': step['end'] - step['start']}
            continue
        label = 'ios-' + step['os']
        summary = xcresult_summary(run_dir / (label + '.xcresult'))
        platform = {
            'os': step['os'], 'device': step['device'], 'runtime_build': step['runtime_build'],
            'state': step['state'], 'exit': step['exit'], 'elapsed': step['end'] - step['start'],
            'passed': None, 'failed': None, 'skipped': None, 'test_time': None,
            'xcresult': label + '.xcresult', 'log': label + '.log', 'failures': [],
            'known_now_passing': [],
            'screen': first(env, 'screen_' + step['os'], 'unknown'),
        }
        if summary:
            platform['passed'] = summary.get('passedTests', 0)
            platform['failed'] = summary.get('failedTests', 0)
            platform['skipped'] = summary.get('skippedTests', 0)
            if summary.get('startTime') and summary.get('finishTime'):
                platform['test_time'] = summary['finishTime'] - summary['startTime']
            grouped = {}
            for failure in summary.get('testFailures', []):
                test = failure.get('testIdentifierString') or failure.get('testName', '?')
                grouped.setdefault(test, []).append(failure.get('failureText', '').strip())
            for test, messages in grouped.items():
                entry = match_known(known, test, step['os'], step['device'])
                if prev_id is None or step['os'] not in prev_failures:
                    history = 'no previous result for this iOS version'
                elif test in prev_failures[step['os']]:
                    history = 'also failed in previous run ' + prev_id
                else:
                    history = 'did not fail in previous run ' + prev_id
                platform['failures'].append({
                    'test': test,
                    'classification': 'listed known' if entry else 'possibly new',
                    'reference': entry['reference'] if entry else '',
                    'previous': history,
                    'message': ' / '.join(messages),
                })
            if not report['only_testing']:
                failing = set(grouped)
                for entry in known:
                    if (entry['os'] in ('*', step['os']) and entry['device'] in ('*', step['device'])
                            and entry['test'] not in failing):
                        platform['known_now_passing'].append(entry['test'])
        if step['state'] == 'ok' and summary and not platform['failed']:
            platform['result'] = 'PASSED'
        elif summary and platform['failed']:
            platform['result'] = 'FAILED'
        elif step['state'] == 'interrupted':
            platform['result'] = 'INTERRUPTED'
        elif step['state'] == 'timeout':
            platform['result'] = 'TIMED OUT'
        else:
            platform['result'] = 'ERROR'
        report['platforms'].append(platform)

    report['status'], report['headline'] = overall(env, report)
    return report


def overall(env, report):
    if 'skipped' in env:
        return 'SKIPPED', 'SKIPPED: ' + first(env, 'skipped')
    if 'setup_error' in env:
        return 'ERROR', 'ERROR: ' + first(env, 'setup_error')
    build = report['build']
    interrupted = 'interrupted' in env
    if build and build['state'] != 'ok':
        if interrupted or build['state'] == 'interrupted':
            return 'INTERRUPTED', 'INTERRUPTED during the build'
        return 'BUILD FAILED', 'BUILD FAILED (%s, exit %d): see build.log' % (build['state'], build['exit'])
    failures = [f for p in report['platforms'] for f in p['failures']]
    new = [f for f in failures if f['classification'] == 'possibly new']
    problems = [p for p in report['platforms'] if p['result'] not in ('PASSED', 'FAILED')]
    parts = []
    if failures:
        parts.append('%d failing test(s): %d possibly new, %d listed known'
                     % (len(failures), len(new), len(failures) - len(new)))
    for platform in problems:
        parts.append('iOS %s %s' % (platform['os'], platform['result'].lower()))
    if interrupted:
        return 'INTERRUPTED', 'INTERRUPTED' + (': ' + '; '.join(parts) if parts else '')
    if not report['platforms']:
        return 'ERROR', 'ERROR: no test runs completed'
    if failures or problems or report['exit_status'] != 0:
        return 'FAILED', 'FAILED: ' + ('; '.join(parts) if parts else 'exit %d' % report['exit_status'])
    return 'PASSED', 'PASSED: all tests passed on %d iOS version(s)' % len(report['platforms'])


def render(report):
    lines = ['# NextSeason nightly tests: ' + report['headline'], '']
    if report['started_at']:
        end = report['finished_at'] or report['started_at']
        lines.append('Run: %s to %s (%s)%s' % (
            clock(report['started_at']), clock(end)[11:], duration(end - report['started_at']),
            '' if report['scheduled'] else ', started manually'))
    if report['sha']:
        where = 'branch %s' % report['branch'] if report['branch'] else report['ref']
        lines.append('Revision: %s on %s, "%s", committed %s (latest commit only; '
                     'uncommitted changes are never tested)'
                     % (report['sha'], where, report['subject'], report['commit_date']))
    elif report['ref']:
        lines.append('Requested revision: ' + report['ref'])
    if report['xcode']:
        lines.append('Toolchain: %s; macOS %s' % (report['xcode'], report['macos']))
    if report['only_testing']:
        lines.append('Subset: only %s (not a full run)' % report['only_testing'].replace('-only-testing:', ''))
    for warning in report['warnings']:
        lines.append('Warning: ' + warning)
    if report['status'] == 'SKIPPED' and report['previous_run']:
        lines.append('Last run with test results: ' + report['previous_run'])
    if report['build']:
        lines.append('Build: %s in %s' % (report['build']['state'], duration(report['build']['elapsed'])))
    for platform in report['platforms']:
        lines += ['', '## iOS %s, %s (runtime %s): %s' % (
            platform['os'], platform['device'], platform['runtime_build'], platform['result'])]
        counts = ''
        if platform['passed'] is not None:
            counts = ', %d passed, %d failed, %d skipped' % (
                platform['passed'], platform['failed'], platform['skipped'])
        test_time = ' (tests %s)' % duration(platform['test_time']) if platform['test_time'] else ''
        lines.append('Elapsed %s%s%s; xcodebuild exit %d'
                     % (duration(platform['elapsed']), test_time, counts, platform['exit']))
        lines.append('Result bundle: %s; log: %s; screen at start: %s'
                     % (platform['xcresult'], platform['log'], platform['screen']))
        if platform['result'] in ('ERROR', 'TIMED OUT', 'INTERRUPTED') and not platform['failures']:
            lines.append('No test failures were recorded; check the log for the cause.')
        for number, failure in enumerate(platform['failures'], 1):
            lines.append('')
            lines.append('%d. %s' % (number, failure['test']))
            if failure['classification'] == 'listed known':
                lines.append('   Listed known failure (%s). Matched by test and environment only; '
                             'confirm the message matches the recorded symptom.' % failure['reference'])
            else:
                lines.append('   Possibly new: not in the known-failures list.')
            lines.append('   History: ' + failure['previous'])
            message = failure['message'].replace('\n', ' ')
            if len(message) > MESSAGE_LIMIT:
                message = message[:MESSAGE_LIMIT] + '...'
            lines.append('   Message: ' + message)
        for test in platform['known_now_passing']:
            lines.append('')
            lines.append('Listed known failure did not fail this run: ' + test)
    lines.append('')
    return '\n'.join(lines)


def history_line(report):
    when = clock(report['started_at']) if report['started_at'] else report['run_id']
    parts = [when, report['status'], report['branch'] or report['ref'] or '-',
             (report['sha'] or '-')[:10]]
    for platform in report['platforms']:
        failed = platform['failed'] or 0
        parts.append('%s:%s' % (platform['os'], 'ok' if platform['result'] == 'PASSED'
                                else '%s(%d)' % (platform['result'].lower(), failed)))
    if report['only_testing']:
        parts.append('subset')
    return '  '.join(parts) + '  ' + report['run_id']


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('run_dir')
    parser.add_argument('--runs-dir')
    parser.add_argument('--known')
    parser.add_argument('--history')
    args = parser.parse_args()
    run_dir = Path(args.run_dir)
    known = read_known(args.known)
    report = build_report(run_dir, known, args.runs_dir)
    if args.known and not Path(args.known).exists():
        report['warnings'].append('known-failures list not found (%s); every failure is '
                                  'reported as possibly new' % args.known)
    text = render(report)
    (run_dir / 'summary.md').write_text(text)
    (run_dir / 'summary.json').write_text(json.dumps(report, indent=2))
    if args.history:
        history = Path(args.history)
        lines = history.read_text().splitlines() if history.exists() else []
        lines = (lines + [history_line(report)])[-500:]
        history.write_text('\n'.join(lines) + '\n')
    sys.stdout.write(text)


if __name__ == '__main__':
    main()
