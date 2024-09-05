#!/usr/bin/env python3

import argparse
import subprocess
import os
import pathlib

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument('-p', '--project', help='The project to stress-test')
    parser.add_argument('-f', '--file-filter', default=None, help='Only stress-test files whose file contains this substring')
    parser.add_argument('-r', '--rewrite-modes', default='none insideOut concurrent', help='Perform the these rewrite modes. (default: %(default)s)')
    parser.add_argument('-o', '--offset-filter', help='If specified, only stress test actions at this offset')
    parser.add_argument('--source-compat-suite', help='Path to the swift-source-compat-suite directory')
    parser.add_argument('--swiftc', required=True, help='Path to the swiftc inside the toolchain to stress-test')
    parser.add_argument('--xcode', help='The Xcode.app whose SDK to use to compile the projects')
    parser.add_argument('--request-durations', default='/tmp/request-durations.json', help='A file where the measured request durations will be saved to')
    return parser.parse_args()

def main():
    args = parse_args()
    if os.path.exists(args.request_durations):
        os.remove(args.request_durations)
    if not args.xcode:
        args.xcode = subprocess.check_output(["xcode-select", "-p"], encoding='utf-8').strip()
    if not args.source_compat_suite:
        args.source_compat_suite = (pathlib.Path(__file__).parent.parent.parent.parent / "swift-source-compat-suite").resolve()
    print(args.source_compat_suite)

    environ = dict(os.environ)
    if args.file_filter:
        environ['SK_STRESS_FILE_FILTER'] = args.file_filter
    environ['SK_STRESS_REWRITE_MODES'] = args.rewrite_modes
    environ['SK_XFAILS_PATH'] = os.path.join(args.source_compat_suite, 'sourcekit-xfails.json')
    environ['DEVELOPER_DIR'] = args.xcode
    environ['CODE_SIGN_IDENTITY'] = ''
    environ['CODE_SIGNING_REQUIRED'] = 'NO'
    environ['ENTITLEMENTS_REQUIRED'] = 'NO'
    environ['ENABLE_BITCODE'] = 'NO'
    environ['INDEX_ENABLE_DATA_STORE'] = 'NO'
    environ['GCC_TREAT_WARNINGS_AS_ERRORS'] = 'NO'
    environ['SWIFT_TREAT_WARNINGS_AS_ERRORS'] = 'NO'
    environ['SK_STRESS_REQUEST_DURATIONS_FILE'] = args.request_durations
    if args.offset_filter:
        environ['SK_OFFSET_FILTER'] = args.offset_filter

    subprocess.call([
        os.path.join(args.source_compat_suite, 'run_sk_stress_test'),
        '--filter-by-project', args.project,
        '--swiftc', args.swiftc,
        '--skip-tools-clone',
        '--skip-tools-build',
        'main'
    ], env=environ)

if __name__ == '__main__':
    main()
