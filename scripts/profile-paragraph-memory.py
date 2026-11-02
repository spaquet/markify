#!/usr/bin/env python3
"""Controlled local GUI memory comparison; requires macOS profiling permissions.

Uses only profiling processes it launches. Writes raw snapshots beside the JSON.
Does not modify documents or persistent preferences. Run after a Release build.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time


def run(args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed ({result.returncode}): {result.stderr}')
    return result.stdout


def pids():
    result = subprocess.run(['pgrep', '-x', 'Markify'], capture_output=True, text=True)
    if result.returncode not in (0, 1):
        raise RuntimeError(result.stderr)
    return set(result.stdout.split())


def settle(pid, start):
    polls = []
    while time.monotonic() - start < 600:
        time.sleep(3)
        status = run(['ps', '-p', pid, '-o', 'pcpu=,time=,etime=']).strip()
        polls.append({'seconds': time.monotonic() - start, 'status': status})
        if float(status.split()[0]) < 5 and time.monotonic() - start >= 15:
            first = time.monotonic() - start
            time.sleep(8)
            status = run(['ps', '-p', pid, '-o', 'pcpu=,time=,etime=']).strip()
            if float(status.split()[0]) < 5:
                return first, status, polls
    raise RuntimeError('Process did not settle within ten minutes')


def snapshot(pid, prefix):
    values = {}
    for label, command in [('footprint', ['footprint', '-p', pid]),
                           ('vmmap', ['vmmap', '-summary', pid]),
                           ('heap', ['heap', '-s', pid])]:
        output = run(command)
        Path(str(prefix) + '-' + label + '.txt').write_text(output)
        for key, pattern in (
            ('physicalFootprintMiB', r'Physical footprint:\s+([\d.]+)M'),
            ('peakFootprintMiB', r'Physical footprint \(peak\):\s+([\d.]+)M'),
            ('attributeRunBytes', r'^\s*\d+\s+(\d+)\s+[\d.]+\s+NSMutableRLEArray.theList'),
            ('liveMallocBytes', r'All zones: \d+ nodes \((\d+) bytes\)'),
        ):
            match = re.search(pattern, output, re.M)
            if match:
                values[key] = float(match[1]) if key.endswith('MiB') else int(match[1])
    return values


def scroll(pid):
    # Page through the beginning, jump to the end, return to the start.
    # This samples distant layout; it does not claim every paragraph was visited.
    return run(['osascript', '-e', f'''
tell application "System Events"
    tell (first application process whose unix id is {pid})
        set frontmost to true
        delay 0.5
        set editorFocused to false
        repeat 10 times
            repeat with editorWindow in every window
                repeat with candidate in (entire contents of editorWindow)
                    try
                        if role of candidate is "AXTextArea" then
                            perform action "AXRaise" of editorWindow
                            set value of attribute "AXFocused" of candidate to true
                            set editorFocused to value of attribute "AXFocused" of candidate
                            if editorFocused then exit repeat
                        end if
                    end try
                end repeat
                if editorFocused then exit repeat
            end repeat
            if editorFocused then exit repeat
            delay 0.5
        end repeat
        if not editorFocused then error "No editor text area found"
        repeat 30 times
            key code 121
            delay 0.08
        end repeat
        key code 125 using command down
        delay 1
        key code 126 using command down
    end tell
end tell
'''])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--repeats', type=int, default=3)
    args = parser.parse_args()
    if pids():
        raise RuntimeError('Markify is already running; refusing to interfere')
    root = Path(__file__).resolve().parents[1]
    workloads = [('blank', []),
                 ('stress-2', [root / 'render-stress-test-2.md']),
                 ('stress-1', [root / 'render-stress-test.md']),
                 ('prose-1m', [Path('/private/tmp/markify-memory-prose-1m.md')]),
                 ('prose-5m', [Path('/private/tmp/markify-memory-prose-5m.md')])]
    for _, files in workloads:
        for path in files:
            if not path.is_file():
                raise FileNotFoundError(path)
    info = args.app / 'Contents/Info.plist'
    version = run(['/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleShortVersionString', str(info)]).strip()
    build = run(['/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleVersion', str(info)]).strip()
    report = {'version': version, 'build': build,
              'executableSHA256': hashlib.sha256((args.app / 'Contents/MacOS/Markify').read_bytes()).hexdigest(),
              'system': run(['sw_vers']), 'navigationFocusChecked': True, 'samples': []}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    for repeat in range(1, args.repeats + 1):
        for name, files in workloads:
            pid = None
            try:
                start = time.monotonic()
                run(['open', '-n', '-a', str(args.app), *map(str, files), '--args',
                     '-startup', 'Blank', '-ApplePersistenceIgnoreState', 'YES',
                     '-defaultLens', 'Rendered', '-rememberLens', 'NO'])
                for _ in range(50):
                    found = pids()
                    if found:
                        break
                    time.sleep(.1)
                if len(found) != 1:
                    raise RuntimeError(f'Expected one profiling process, got {found}')
                pid = found.pop()
                idle, status, polls = settle(pid, start)
                prefix = args.output.with_suffix('').with_name(args.output.stem + f'-{name}-{repeat}')
                row = {'workload': name, 'repeat': repeat, 'firstObservedIdleSeconds': idle,
                       'status': status, 'polls': polls,
                       'documents': [{'path': str(p), 'bytes': p.stat().st_size,
                                      'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in files],
                       'initial': snapshot(pid, Path(str(prefix) + '-initial'))}
                if files:
                    try:
                        scroll(pid)
                        row['navigationFocusVerified'] = True
                        _, row['afterScrollStatus'], _ = settle(pid, time.monotonic())
                        row['afterScroll'] = snapshot(pid, Path(str(prefix) + '-scrolled'))
                    except RuntimeError as error:
                        # Preserve the valid initial sample if OS accessibility does not expose
                        # this window. Never label unverified keyboard events as a scroll test.
                        row['navigationFocusVerified'] = False
                        row['navigationError'] = str(error)
                report['samples'].append(row)
                args.output.write_text(json.dumps(report, indent=2) + '\n')
                print(json.dumps({k: v for k, v in row.items() if k not in ('polls', 'documents')}), flush=True)
            finally:
                if pid is not None and pid in pids():
                    os.kill(int(pid), signal.SIGTERM)
                    for _ in range(100):
                        if pid not in pids():
                            break
                        time.sleep(.1)
                    else:
                        raise RuntimeError('Profiling process did not terminate')


if __name__ == '__main__':
    main()
