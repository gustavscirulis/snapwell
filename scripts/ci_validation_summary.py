#!/usr/bin/env python3
"""Export only allowlisted validation facts; raw logs and xcresults stay on the runner."""
import argparse
import json
from pathlib import Path
import re
import subprocess

HEADLESS = {'tooling-python', 'tooling-swift', 'core'}
COUNTS = ('totalTestCount', 'passedTests', 'failedTests', 'skippedTests')


def diagnostics(report):
    """Keep failure triage useful without publishing test output or machine details."""
    statuses = {'passed', 'failed', 'timed_out', 'unavailable'}
    result = {'suites': {item['name']: item['status'] for item in report.get('results', [])
                         if item.get('name') in HEADLESS | {'macos', 'ios'}
                         and item.get('status') in statuses}}
    # Error locations only: never echo source lines, compiler messages or absolute paths.
    locations = set()
    for item in report.get('results', []):
        if item.get('name') not in ('macos', 'ios') or item.get('status') != 'failed':
            continue
        path = Path(item.get('log', ''))
        if not path.is_file():
            continue
        for match in re.finditer(r'/(ios|macos|Shared)/([A-Za-z0-9_+./-]+\.swift):(\d+):(\d+): error:',
                                 path.read_text(errors='replace')):
            locations.add((match[1] + '/' + match[2], int(match[3]), int(match[4])))
    if locations:
        result['compiler_error_locations'] = [dict(file=file, line=line, column=column)
                                              for file, line, column in sorted(locations)]
    return result


def sanitized(report, native, commit):
    if not re.fullmatch(r'[a-f0-9]{40,64}', commit):
        raise RuntimeError('Invalid source commit')
    if not report.get('results') or report.get('suite') != 'all':
        raise RuntimeError('Expected complete validation evidence')
    result = {'source_commit': commit, 'headless': {}, 'native': {}}
    for item in report['results']:
        name = item['name']
        if name not in HEADLESS | {'macos', 'ios'} or item['status'] != 'passed':
            raise RuntimeError('Validation contains a failed, unavailable or unknown suite')
        if name in HEADLESS:
            result['headless'][name] = 'passed'
        else:
            counts = {key: native[name].get(key) for key in COUNTS}
            if (any(type(value) is not int for value in counts.values()) or counts['totalTestCount'] <= 0
                    or counts['failedTests'] != 0 or counts['skippedTests'] != 0
                    or counts['passedTests'] != counts['totalTestCount']):
                raise RuntimeError('Native result bundle did not pass all tests without skips')
            result['native'][name] = counts
    if set(result['headless']) != HEADLESS or set(result['native']) != set(report.get('platforms', [])):
        raise RuntimeError('Validation evidence is incomplete')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default='.context/public-validation.json')
    parser.add_argument('--diagnostics', action='store_true', help='Print only allowlisted suite states, including failures')
    args = parser.parse_args()
    reports = list(Path('.context/testing').glob('*/summary.json'))
    if not reports:
        raise RuntimeError('No native validation report')
    path = max(reports, key=lambda path: path.stat().st_mtime_ns)
    report = json.loads(path.read_text())
    if args.diagnostics:
        print(json.dumps(diagnostics(report), sort_keys=True))
        return
    native = {}
    for platform in report.get('platforms', []):
        if platform not in ('macos', 'ios'):
            raise RuntimeError('Unexpected platform')
        raw = subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                       '--path', str(path.parent / (platform + '.xcresult'))])
        native[platform] = json.loads(raw)
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD']).decode().strip()
    result = sanitized(report, native, commit)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    main()
