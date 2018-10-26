#!/usr/bin/env python

"""
  This source file is part of the Swift.org open source project
 
  Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
  Licensed under Apache License v2.0 with Runtime Library Exception

  See https://swift.org/LICENSE.txt for license information
  See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

 ------------------------------------------------------------------------------
 This is a helper script for the main swift repository's build-script.py that
 knows how to build and install the stress tester utilities given a swift
 workspace. It additionally copies in the SwiftSyntax dylib as its not
 currently installed.

"""

from __future__ import print_function

import argparse
import sys
import os
import shutil
import subprocess

PACKAGE_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))

def main():
  args = parse_args(sys.argv[1:])
  args.func(args)


def parse_args(args):
  # create the top-level parser
  parser = argparse.ArgumentParser(prog='BUILD-SCRIPT-HELPER.PY')
  parser.add_argument('-v', '--verbose', action='store_true', help='log executed commands')
  subparsers = parser.add_subparsers(help='command to run')

  # create the parser for the "install" command
  install_parser = subparsers.add_parser('install', help='install the stress tester into a swift toolchain')
  install_parser.add_argument('install_dir', help='path to the toolchain\'s usr directory')
  install_parser.add_argument('--config', default='release')
  install_parser.add_argument('--swiftpm-build-dir', required=True, help='swift-build and swift-test will be used to build this package')
  install_parser.add_argument('--swift-build-dir', required=True, help='needed to strip local rpaths from binaries')
  install_parser.add_argument('--swiftsyntax-build-dir', help='needed to copy libswiftSyntax.dylib into install_dir')
  install_parser.set_defaults(func=install_command)

  return parser.parse_args(args)


def install_command(args):
  output_dir = build_package(swift_build_exec=os.path.join(args.swiftpm_build_dir, 'swift-build'),
    sourcekit_searchpath=os.path.join(args.install_dir, 'usr', 'lib'),
    swiftsyntax_searchpath=args.swiftsyntax_build_dir,
    rpaths=['@executable_path/../lib/swift/macosx', '@executable_path/../lib'],
    build_dir=os.path.join(PACKAGE_DIR, '.install'),
    config='release',
    verbose=args.verbose)

  install_package(install_dir=args.install_dir,
    build_dir=output_dir,
    swift_build_dir=args.swift_build_dir,
    swiftsyntax_build_dir=args.swiftsyntax_build_dir,
    rpaths_to_delete=[os.path.join(args.swift_build_dir, 'lib', 'swift', 'macosx')],
    verbose=args.verbose)


def install_package(install_dir, build_dir, swift_build_dir, swiftsyntax_build_dir, rpaths_to_delete=[], verbose=False):
  stress_tester = os.path.join(build_dir, 'sk-stress-test')
  swiftc_wrapper = os.path.join(build_dir, 'sk-swiftc-wrapper')
  bin_dir = os.path.join(install_dir, 'usr', 'bin')
  lib_dir = os.path.join(install_dir, 'usr', 'lib', 'swift', 'macosx')
  swiftsyntax_src = os.path.join(swiftsyntax_build_dir, 'libSwiftSyntax.dylib')
  swiftsyntax_dest = os.path.join(lib_dir, 'libswiftSwiftSyntax.dylib')

  for directory in [bin_dir, lib_dir]:
    if not os.path.exists(directory):
      os.makedirs(directory)

  # FIXME: this should probably be handled in a swiftsyntax install
  shutil.copy2(swiftsyntax_src, swiftsyntax_dest)
  for rpath in rpaths_to_delete:
    remove_rpath(swiftsyntax_dest, rpath)
  check_call(['install_name_tool', '-id', '@rpath/libswiftSwiftSyntax.dylib', swiftsyntax_dest], verbose=verbose)

  for executable in [stress_tester, swiftc_wrapper]:
    dest = os.path.join(bin_dir, os.path.basename(executable))
    shutil.copy2(executable, dest)
    for rpath in rpaths_to_delete:
      remove_rpath(dest, rpath)
    check_call(['install_name_tool', '-change', os.path.realpath(swiftsyntax_src), '@rpath/libswiftSwiftSyntax.dylib', dest], verbose=verbose)


def build_package(swift_build_exec, sourcekit_searchpath, swiftsyntax_searchpath, rpaths=None, build_dir='.build', config='release', verbose=False):
  if not rpaths:
    rpaths = [sourcekit_searchpath, swiftsyntax_searchpath]

  def interleave(value, list):
    return [item for pair in zip([value] * len(list), list) for item in pair]

  swiftc_args = ['-lSwiftSyntax', '-I', swiftsyntax_searchpath, '-L', swiftsyntax_searchpath, '-Fsystem', sourcekit_searchpath]
  linker_args = interleave('-rpath', rpaths)

  args = [swift_build_exec, '--package-path', PACKAGE_DIR, '-c', config, '--build-path', build_dir] + interleave('-Xswiftc', swiftc_args) + interleave('-Xlinker', linker_args)
  check_call(args, verbose=verbose)
  return check_output(args + ['--show-bin-path']).rstrip()


def remove_rpath(binary, rpath):
  cmd = ['install_name_tool', '-delete_rpath', os.path.realpath(rpath), binary]
  check_call(cmd)


def check_output(cmd, env=os.environ, verbose=False, **kwargs):
  if verbose:
    print(' '.join([escape_cmd_arg(arg) for arg in cmd]))
  return subprocess.check_output(cmd, stderr=subprocess.STDOUT, **kwargs)

def check_call(cmd, env=os.environ, verbose=False, **kwargs):
  if verbose:
    print(' '.join([escape_cmd_arg(arg) for arg in cmd]))
  return subprocess.check_call(cmd, stderr=subprocess.STDOUT, **kwargs)


def find_executable(executable, beside=None, toolchain=None):
  if beside:
    path = os.path.join(os.path.dirname(beside), executable)
    if os.path.isfile(path):
      return path
  extra_args = ['--toolchain', toolchain] if toolchain else []
  return check_output(['xcrun', '-f', executable] + extra_args).rstrip()


def escape_cmd_arg(arg):
  if '"' in arg or ' ' in arg:
    return '"%s"' % arg.replace('"', '\\"')
  else:
    return arg

if __name__ == '__main__':
  main()
