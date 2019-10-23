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
 workspace.

"""

from __future__ import print_function

import argparse
import sys
import os, platform
import subprocess

def printerr(message):
    print(message, file=sys.stderr)

def main(argv_prefix = []):
  args = parse_args(argv_prefix + sys.argv[1:])
  run(args)

def parse_args(args):
  parser = argparse.ArgumentParser(prog='BUILD-SCRIPT-HELPER.PY')

  parser.add_argument('--package-dir', default='SourceKitStressTester')
  parser.add_argument('-v', '--verbose', action='store_true', help='log executed commands')
  parser.add_argument('--prefix', help='install path')
  parser.add_argument('--config', default='release')
  parser.add_argument('--build-dir', default='.build')
  parser.add_argument('--toolchain', required=True, help='the toolchain to use when building this package')
  parser.add_argument('build_actions', help="Extra actions to perform. Can be any number of the following", choices=['all', 'build', 'test', 'install', 'generate-xcodeproj'], nargs="*", default=['build'])

  parsed = parser.parse_args(args)

  if ("install" in parsed.build_actions or "all" in parsed.build_actions) and not parsed.prefix:
    ArgumentParser.error("'--prefix' is required with the install action")
  parsed.swift_exec = os.path.join(parsed.toolchain, 'usr', 'bin', 'swift')

  parsed.sourcekitd_dir = os.path.join(parsed.toolchain, 'usr', 'lib')

  # Convert package_dir to absolute path, relative to root of repo.
  repo_path = os.path.dirname(__file__)
  parsed.package_dir = os.path.realpath(
                        os.path.join(repo_path, parsed.package_dir))

  # Convert build_dir to absolute path, relative to package_dir.
  parsed.build_dir = os.path.join(parsed.package_dir, parsed.build_dir)

  return parsed

def run(args):
  sourcekit_searchpath=args.sourcekitd_dir
  package_name = os.path.basename(args.package_dir)

  # The test action creates its own build. No need to build if we are just testing
  if should_run_any_action(['build', 'install'], args.build_actions):
    print("** Building %s **" % package_name)
    try:
      invoke_swift(package_dir=args.package_dir,
        swift_exec=args.swift_exec,
        action='build',
        sourcekit_searchpath=sourcekit_searchpath,
        build_dir=args.build_dir,
        config=args.config,
        verbose=args.verbose)
    except subprocess.CalledProcessError as e:
      printerr('FAIL: Building %s failed' % package_name)
      printerr('Executing: %s' % ' '.join(e.cmd))
      sys.exit(1)

  output_dir = os.path.realpath(os.path.join(args.build_dir, args.config))

  if should_run_action("generate-xcodeproj", args.build_actions):
    print("** Generating Xcode project for %s **" % package_name)
    try:
      generate_xcodeproj(args.package_dir,
        swift_exec=args.swift_exec,
        sourcekit_searchpath=sourcekit_searchpath,
        verbose=args.verbose)
    except subprocess.CalledProcessError as e:
      printerr('FAIL: Generating the Xcode project failed')
      printerr('Executing: %s' % ' '.join(e.cmd))
      sys.exit(1)

  if should_run_action("test", args.build_actions):
    print("** Testing %s **" % package_name)
    try:
      invoke_swift(package_dir=args.package_dir,
        swift_exec=args.swift_exec,
        action='test',
        sourcekit_searchpath=sourcekit_searchpath,
        # note: test uses a different build_dir so it doesn't interfere with the 'build' step's products before install
        build_dir=os.path.join(args.build_dir, 'test-build'),
        config='debug',
        verbose=args.verbose)
    except subprocess.CalledProcessError as e:
      printerr('FAIL: Testing %s failed' % package_name)
      printerr('Executing: %s' % ' '.join(e.cmd))
      sys.exit(1)

  if should_run_action("install", args.build_actions):
    print("** Installing %s **" % package_name)
    stdlib_dir = os.path.join(args.toolchain, 'usr', 'lib', 'swift', 'macosx')
    try:
      install_package(args.package_dir,
        install_dir=args.prefix,
        sourcekit_searchpath=sourcekit_searchpath,
        build_dir=output_dir,
        rpaths_to_delete=[stdlib_dir],
        verbose=args.verbose)
    except subprocess.CalledProcessError as e:
      printerr('FAIL: Installing %s failed' % package_name)
      printerr('Executing: %s' % ' '.join(e.cmd))
      sys.exit(1)


# Returns true if any of the actions in `action_names` should be run.
def should_run_any_action(action_names, selected_actions):
  for action_name in action_names:
    if should_run_action(action_name, selected_actions):
      return True
  return False


def should_run_action(action_name, selected_actions):
  if action_name in selected_actions:
    return True
  elif "all" in selected_actions:
    return True
  else:
    return False


def invoke_swift(package_dir, action, swift_exec, sourcekit_searchpath, build_dir, config, verbose):
  swiftc_args = ['-Fsystem', sourcekit_searchpath]
  linker_args = ['-rpath', sourcekit_searchpath]


  args = [swift_exec, action, '--package-path', package_dir, '-c', config, '--build-path', build_dir] + interleave('-Xswiftc', swiftc_args) + interleave('-Xlinker', linker_args)
  check_call(args, verbose=verbose)


def install_package(package_dir, install_dir, sourcekit_searchpath, build_dir, rpaths_to_delete, verbose):
  bin_dir = os.path.join(install_dir, 'bin')
  lib_dir = os.path.join(install_dir, 'lib', 'swift', 'macosx')

  for directory in [bin_dir, lib_dir]:
    if not os.path.exists(directory):
      os.makedirs(directory)

  rpaths_to_delete += [sourcekit_searchpath]
  rpaths_to_add = ['@executable_path/../lib/swift/macosx', '@executable_path/../lib']

  # Install sk-stress-test and sk-swiftc-wrapper
  for product in get_products(package_dir):
    src = os.path.join(build_dir, product)
    dest = os.path.join(bin_dir, product)

    install(src, dest,
      rpaths_to_delete=rpaths_to_delete,
      rpaths_to_add=rpaths_to_add,
      verbose=verbose)

def install(src, dest, rpaths_to_delete, rpaths_to_add, verbose):
  copy_cmd=['rsync', '-a', src, dest]
  print('installing %s to %s' % (os.path.basename(src), dest))
  check_call(copy_cmd, verbose=verbose)

  for rpath in rpaths_to_delete:
    remove_rpath(dest, rpath, verbose=verbose)
  for rpath in rpaths_to_add:
    add_rpath(dest, rpath, verbose=verbose)

def generate_xcodeproj(package_dir, swift_exec, sourcekit_searchpath, verbose):
  package_name = os.path.basename(package_dir)
  config_path = os.path.join(package_dir, 'Config.xcconfig')
  with open(config_path, 'w') as config_file:
    config_file.write('''
      SYSTEM_FRAMEWORK_SEARCH_PATHS = {sourcekit_searchpath} $(inherited)
      LD_RUNPATH_SEARCH_PATHS = {sourcekit_searchpath} $(inherited)
    '''.format(sourcekit_searchpath=sourcekit_searchpath))

  xcodeproj_path = os.path.join(package_dir, '%s.xcodeproj' % package_name)

  args = [swift_exec, 'package', '--package-path', package_dir, 'generate-xcodeproj', '--xcconfig-overrides', config_path, '--output', xcodeproj_path]
  check_call(args, verbose=verbose)

def add_rpath(binary, rpath, verbose):
  cmd = ['install_name_tool', '-add_rpath', rpath, binary]
  check_call(cmd, verbose=verbose)


def remove_rpath(binary, rpath, verbose):
  cmd = ['install_name_tool', '-delete_rpath', rpath, binary]
  check_call(cmd, verbose=verbose)


def check_call(cmd, verbose, env=os.environ, **kwargs):
  if verbose:
    print(' '.join([escape_cmd_arg(arg) for arg in cmd]))
  return subprocess.check_call(cmd, env=env, stderr=subprocess.STDOUT, **kwargs)


def interleave(value, list):
    return [item for pair in zip([value] * len(list), list) for item in pair]


def escape_cmd_arg(arg):
  if '"' in arg or ' ' in arg:
    return '"%s"' % arg.replace('"', '\\"')
  else:
    return arg

def get_products(package_dir):
  # FIXME: We ought to be able to query SwiftPM for this info.
  if package_dir.endswith("/SourceKitStressTester"):
    return ['sk-stress-test', 'sk-swiftc-wrapper']
  elif package_dir.endswith("/SwiftEvolve"):
    return ['swift-evolve']
  else:
    return []

if __name__ == '__main__':
  main()
