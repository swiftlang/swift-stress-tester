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
  run(args)


def parse_args(args):
  parser = argparse.ArgumentParser(prog='BUILD-SCRIPT-HELPER.PY')
  parser.add_argument('-v', '--verbose', action='store_true', help='log executed commands')
  parser.add_argument('--prefix', help='install path')
  parser.add_argument('--config', default='release')
  parser.add_argument('--build-dir', default=os.path.join(PACKAGE_DIR, '.build'))
  parser.add_argument('--swiftpm-build-dir', required=True, help='swift-build and swift-test will be used to build this package')
  parser.add_argument('--swift-build-dir', required=True, help='needed to strip local rpaths from binaries')
  parser.add_argument('--swiftsyntax-build-dir', required=True, help='needed to copy libswiftSyntax.dylib into install_dir')
  parser.add_argument('build_actions', help="Extra actions to perform. Can be any number of the following: [all, test, install]", nargs="*", default=[])

  parsed = parser.parse_args(args)
  if "install" in parsed.build_actions or "all" in parsed.build_actions:
    if not parsed.prefix:
      ArgumentParser.error("'--prefix' is required with the install action")

  return parsed


def run(args):
  sourcekit_searchpath=os.path.join(args.swift_build_dir, 'lib')
  swiftsyntax_searchpath=args.swiftsyntax_build_dir

  print("** Building Swift Stress Tester **")
  build_package(swift_build_exec=os.path.join(args.swiftpm_build_dir, 'swift-build'),
    sourcekit_searchpath=sourcekit_searchpath,
    swiftsyntax_searchpath=swiftsyntax_searchpath,
    build_dir=args.build_dir,
    config=args.config,
    verbose=args.verbose)

  output_dir = os.path.realpath(os.path.join(args.build_dir, args.config))

  if "test" in args.build_actions or "all" in args.build_actions:
    print("** Testing Swift Stress Tester **")
    build_package(swift_build_exec=os.path.join(args.swiftpm_build_dir, 'swift-test'),
    sourcekit_searchpath=sourcekit_searchpath,
    swiftsyntax_searchpath=swiftsyntax_searchpath,
    #rpaths=['@executable_path/../lib/swift/macosx', '@executable_path/../lib'],
    build_dir=args.build_dir,
    config='debug',
    verbose=args.verbose)

  if "install" in args.build_actions or "all" in args.build_actions:
    print("** Installing Swift Stress Tester **")
    install_package(install_dir=args.prefix,
      sourcekit_searchpath=sourcekit_searchpath,
      swiftsyntax_searchpath=swiftsyntax_searchpath,
      build_dir=output_dir,
      rpaths_to_delete=[os.path.join(args.swift_build_dir, 'lib', 'swift', 'macosx')],
      verbose=args.verbose)


def build_package(swift_build_exec, sourcekit_searchpath, swiftsyntax_searchpath, build_dir, config='release', verbose=False):
  def interleave(value, list):
    return [item for pair in zip([value] * len(list), list) for item in pair]

  swiftc_args = ['-lSwiftSyntax', '-I', swiftsyntax_searchpath, '-L', swiftsyntax_searchpath, '-Fsystem', sourcekit_searchpath]
  linker_args = ['-rpath', sourcekit_searchpath, '-rpath', swiftsyntax_searchpath]

  args = [swift_build_exec, '--package-path', PACKAGE_DIR, '-c', config, '--build-path', build_dir] + interleave('-Xswiftc', swiftc_args) + interleave('-Xlinker', linker_args)
  check_call(args, verbose=verbose)


def install_package(install_dir, sourcekit_searchpath, swiftsyntax_searchpath, build_dir, rpaths_to_delete=[], verbose=False):
  stress_tester = os.path.join(build_dir, 'sk-stress-test')
  swiftc_wrapper = os.path.join(build_dir, 'sk-swiftc-wrapper')
  bin_dir = os.path.join(install_dir, 'bin')
  lib_dir = os.path.join(install_dir, 'lib', 'swift', 'macosx')

  swiftsyntax_src = os.path.join(swiftsyntax_searchpath, 'libSwiftSyntax.dylib')
  swiftsyntax_dest = os.path.join(lib_dir, 'libswiftSwiftSyntax.dylib')

  for directory in [bin_dir, lib_dir]:
    if not os.path.exists(directory):
      os.makedirs(directory)

  # FIXME: this should probably be handled in a swiftsyntax install
  shutil.copy2(swiftsyntax_src, swiftsyntax_dest)
  for rpath in rpaths_to_delete:
    remove_rpath(swiftsyntax_dest, rpath)
  check_call(['install_name_tool', '-id', '@rpath/libswiftSwiftSyntax.dylib', swiftsyntax_dest], verbose=verbose)

  rpaths_to_delete += [sourcekit_searchpath, swiftsyntax_searchpath]
  rpaths_to_add = ['@executable_path/../lib', '@executable_path/../lib/swift/macosx']
  for executable in [stress_tester, swiftc_wrapper]:
    dest = os.path.join(bin_dir, os.path.basename(executable))
    try:
      os.remove(dest)
    except FileNotFoundError:
      pass
    shutil.copy2(executable, dest)
    for rpath in rpaths_to_delete:
      remove_rpath(dest, rpath)
    for rpath in rpaths_to_add:
      add_rpath(dest, rpath)
    check_call(['install_name_tool', '-change', os.path.realpath(swiftsyntax_src), '@rpath/libswiftSwiftSyntax.dylib', dest], verbose=verbose)

def add_rpath(binary, rpath):
  cmd = ['install_name_tool', '-add_rpath', rpath, binary]
  check_call(cmd)

def remove_rpath(binary, rpath):
  cmd = ['install_name_tool', '-delete_rpath', rpath, binary]
  check_call(cmd)


def check_output(cmd, env=os.environ, verbose=False, **kwargs):
  if verbose:
    print(' '.join([escape_cmd_arg(arg) for arg in cmd]))
  return subprocess.check_output(cmd, env=env, stderr=subprocess.STDOUT, **kwargs)


def check_call(cmd, env=os.environ, verbose=False, **kwargs):
  if verbose:
    print(' '.join([escape_cmd_arg(arg) for arg in cmd]))
  return subprocess.check_call(cmd, env=env, stderr=subprocess.STDOUT, **kwargs)


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
