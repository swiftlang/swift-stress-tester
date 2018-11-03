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
  parser.add_argument('--swiftc-exec', help='the compiler to use when building this package (default: xcrun -f swiftc)')
  parser.add_argument('--swift-build-exec', help='the swift-build exec to use to build this package (default: xcrun -f swift-build)')
  parser.add_argument('--swift-test-exec', help='the swift-test exec to use to test this package (default: xcrun -f swift-test)')
  parser.add_argument('--sourcekitd-dir', help='the directory containing the sourcekitd.framework to use (default: relative to swiftc-exec)')
  parser.add_argument('--swiftsyntax-dir', required=True, help='the directory containing SwiftSyntax\'s build products (libSwiftSyntax.dylib, and SwiftSyntax.swiftmodule)')
  parser.add_argument('build_actions', help="Extra actions to perform. Can be any number of the following: [all, test, install]", nargs="*", default=[])

  parsed = parser.parse_args(args)

  if ("install" in parsed.build_actions or "all" in parsed.build_actions) and not parsed.prefix:
    ArgumentParser.error("'--prefix' is required with the install action")
  if parsed.swiftc_exec is None:
    parsed.swiftc_exec = find_executable('swiftc')
  if parsed.swift_build_exec is None:
    parsed.swift_build_exec = find_executable('swift-build')
  if parsed.swift_test_exec is None:
    parsed.swift_test_exec = find_executable('swift-test')
  if parsed.sourcekitd_dir is None:
    parsed.sourcekitd_dir = os.path.join(os.path.dirname(os.path.dirname(parsed.swiftc_exec)), 'lib')

  return parsed


def run(args):
  sourcekit_searchpath=args.sourcekitd_dir
  swiftsyntax_searchpath=args.swiftsyntax_dir

  print("** Building Swift Stress Tester **")
  build_package(swift_build_exec=args.swift_build_exec,
    swiftc_exec=args.swiftc_exec,
    sourcekit_searchpath=sourcekit_searchpath,
    swiftsyntax_searchpath=swiftsyntax_searchpath,
    build_dir=args.build_dir,
    config=args.config,
    verbose=args.verbose)

  output_dir = os.path.realpath(os.path.join(args.build_dir, args.config))

  if "test" in args.build_actions or "all" in args.build_actions:
    print("** Testing Swift Stress Tester **")
    build_package(swift_build_exec=args.swift_test_exec,
    swiftc_exec=args.swiftc_exec,
    sourcekit_searchpath=sourcekit_searchpath,
    swiftsyntax_searchpath=swiftsyntax_searchpath,
    # note: test uses a different build_dir so it doesn't intefer with the 'build' step's products before install
    build_dir=os.path.join(args.build_dir, 'test-build'),
    config='debug',
    verbose=args.verbose)

  if "install" in args.build_actions or "all" in args.build_actions:
    print("** Installing Swift Stress Tester **")
    stdlib_dir = os.path.join(os.path.dirname(os.path.dirname(args.swiftc_exec)), 'lib', 'swift', 'macosx')
    install_package(install_dir=args.prefix,
      sourcekit_searchpath=sourcekit_searchpath,
      swiftsyntax_searchpath=swiftsyntax_searchpath,
      build_dir=output_dir,
      rpaths_to_delete=[stdlib_dir],
      verbose=args.verbose)


def build_package(swift_build_exec, swiftc_exec, sourcekit_searchpath, swiftsyntax_searchpath, build_dir, config='release', verbose=False):
  env = os.environ
  env['SWIFT_EXEC'] = swiftc_exec

  swiftc_args = ['-lSwiftSyntax', '-I', swiftsyntax_searchpath, '-L', swiftsyntax_searchpath, '-Fsystem', sourcekit_searchpath]
  linker_args = ['-rpath', swiftsyntax_searchpath, '-rpath', sourcekit_searchpath]
  args = [swift_build_exec, '--package-path', PACKAGE_DIR, '-c', config, '--build-path', build_dir] + interleave('-Xswiftc', swiftc_args) + interleave('-Xlinker', linker_args)
  check_call(args, env=env, verbose=verbose)


def install_package(install_dir, sourcekit_searchpath, swiftsyntax_searchpath, build_dir, rpaths_to_delete=[], verbose=False):
  bin_dir = os.path.join(install_dir, 'bin')
  lib_dir = os.path.join(install_dir, 'lib', 'swift', 'macosx')

  for directory in [bin_dir, lib_dir]:
    if not os.path.exists(directory):
      os.makedirs(directory)

  # Install SwiftSyntax dylib
  # FIXME: this should probably be handled elsewhere
  swiftsyntax_src = os.path.join(swiftsyntax_searchpath, 'libSwiftSyntax.dylib')
  swiftsyntax_dest = os.path.join(lib_dir, 'libswiftSwiftSyntax.dylib')

  install(swiftsyntax_src, swiftsyntax_dest,
    rpaths_to_delete=rpaths_to_delete,
    dylib_id='@rpath/libswiftSwiftSyntax.dylib',
    verbose=verbose)

  # Install sk-stress-test and sk-swiftc-wrapper
  wrapper_src = os.path.join(build_dir, 'sk-swiftc-wrapper')
  wrapper_dest = os.path.join(bin_dir, 'sk-swiftc-wrapper')
  stress_tester_src = os.path.join(build_dir, 'sk-stress-test')
  stress_tester_dest = os.path.join(bin_dir, 'sk-stress-test')
  rpaths_to_delete += [sourcekit_searchpath, swiftsyntax_searchpath]
  rpaths_to_add = ['@executable_path/../lib/swift/macosx', '@executable_path/../lib']
  loadpath_changes = {os.path.realpath(swiftsyntax_src): '@rpath/libswiftSwiftSyntax.dylib'}

  install(wrapper_src, wrapper_dest,
    rpaths_to_delete=rpaths_to_delete,
    rpaths_to_add=rpaths_to_add,
    loadpath_changes=loadpath_changes,
    verbose=verbose)
  install(stress_tester_src, stress_tester_dest,
    rpaths_to_delete=rpaths_to_delete,
    rpaths_to_add=rpaths_to_add,
    loadpath_changes=loadpath_changes,
    verbose=verbose)


def install(src, dest, rpaths_to_delete=[], rpaths_to_add=[], loadpath_changes={}, dylib_id=None, verbose=False):
  remove_if_present(dest)
  shutil.copy2(src, dest)

  if dylib_id is not None:
    check_call(['install_name_tool', '-id', dylib_id, dest])

  for rpath in rpaths_to_delete:
    remove_rpath(dest, rpath)
  for rpath in rpaths_to_add:
    add_rpath(dest, rpath)

  for key, value in loadpath_changes.iteritems():
    check_call(['install_name_tool', '-change', key, value, dest])


def add_rpath(binary, rpath):
  cmd = ['install_name_tool', '-add_rpath', rpath, binary]
  check_call(cmd)


def remove_rpath(binary, rpath):
  cmd = ['install_name_tool', '-delete_rpath', rpath, binary]
  check_call(cmd)


def remove_if_present(path):
  try:
    os.remove(path)
  except FileNotFoundError:
    pass


def check_output(cmd, env=os.environ, verbose=False, **kwargs):
  if verbose:
    print(' '.join([escape_cmd_arg(arg) for arg in cmd]))
  return subprocess.check_output(cmd, env=env, stderr=subprocess.STDOUT, **kwargs)


def check_call(cmd, env=os.environ, verbose=False, **kwargs):
  if verbose:
    print(' '.join([escape_cmd_arg(arg) for arg in cmd]))
  return subprocess.check_call(cmd, env=env, stderr=subprocess.STDOUT, **kwargs)


def interleave(value, list):
    return [item for pair in zip([value] * len(list), list) for item in pair]


def find_executable(executable, toolchain=None):
  if os.path.isfile(executable) and os.access(executable, os.X_OK):
      return executable
  extra_args = ['--toolchain', toolchain] if toolchain else []
  return check_output(['xcrun', '-f', executable] + extra_args).rstrip()


def escape_cmd_arg(arg):
  if '"' in arg or ' ' in arg:
    return '"%s"' % arg.replace('"', '\\"')
  else:
    return arg

if __name__ == '__main__':
  main()
