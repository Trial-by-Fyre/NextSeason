#!/usr/bin/env python3
"""Export app console events and HTTP HAR from a saved Instruments trace."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import runpy
import subprocess
import tempfile
from xml.etree import ElementTree as ET


def merge_har_files(directory: Path) -> dict:
    documents = []
    for path in sorted(directory.rglob('*.har')):
        data = json.loads(path.read_text())
        if not isinstance(data, dict) or not isinstance(data.get('log'), dict):
            raise ValueError('HAR export has no log object')
        entries = data['log'].get('entries')
        if not isinstance(entries, list):
            raise ValueError('HAR export has no log.entries array')
        for entry in entries:
            if not isinstance(entry, dict) or not isinstance(entry.get('request'), dict) or not isinstance(entry['request'].get('url'), str):
                raise ValueError('HAR export contains an invalid request')
        documents.append(data)
    if not documents or not any(d['log']['entries'] for d in documents):
        raise ValueError('HAR export contains no requests')
    result = documents[0]
    result['log']['entries'] = [entry for d in documents for entry in d['log']['entries']]
    return result


def console_lines(xml: str) -> list[str]:
    api = runpy.run_path(str(Path(__file__).with_name('analyze-performance-traces.py')))
    data = api['TraceXML'](xml)
    lines = []
    seen = set()
    for row in data.root.findall('.//row'):
        def text(tag):
            cell = data.cell(row, tag)
            return (cell.get('fmt') or cell.text or '') if cell is not None else ''
        process = text('process')
        if not process.startswith('NextSeason ('):
            continue
        # HTTP Traffic also encodes full HAR payloads as os_log data. Keep these
        # in the HAR artifact, not in a readable console report.
        if text('category') == 'HAR':
            continue
        message = text('os-log-metadata') or text('format-string')
        if not message:
            continue
        event = (text('event-time'), process, text('event-type'), text('subsystem'), text('category'), message)
        if event in seen:
            continue
        seen.add(event)
        lines.append(f'{event[0]} {process} [{event[3]}:{event[4]}] {event[2].lower()}: {message}')
    return lines


def export(trace: Path, log: Path | None, har: Path | None) -> None:
    if har is not None:
        har.unlink(missing_ok=True)
        with tempfile.TemporaryDirectory(prefix='nextseason-har-') as directory:
            subprocess.run(['xcrun','xctrace','export','--input',str(trace),'--har','--output',directory], check=True, timeout=45, capture_output=True)
            data = merge_har_files(Path(directory))
        har.write_text(json.dumps(data))
    if log is not None:
        log.write_text('')
        result = subprocess.run(['xcrun','xctrace','export','--input',str(trace),'--xpath','/trace-toc/run[@number="1"]/data/table[@schema="os-log"]'],check=True,timeout=45,capture_output=True,text=True)
        lines = console_lines(result.stdout)
        if not lines:
            raise ValueError('trace contains no readable app console events')
        log.write_text('\n'.join(lines)+'\n')


def main() -> int:
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('trace',type=Path)
    p.add_argument('--log',type=Path)
    p.add_argument('--har',type=Path)
    args=p.parse_args()
    if args.log is None and args.har is None:
        p.error('provide --log and/or --har')
    try:
        export(args.trace,args.log,args.har)
    except (OSError,ValueError,ET.ParseError,subprocess.SubprocessError) as error:
        # Diagnostics stay on stderr; they must never count as captured app logs.
        print(f'warning: trace evidence export failed: {error}',file=__import__('sys').stderr)
        return 1
    return 0


if __name__=='__main__':
    raise SystemExit(main())
