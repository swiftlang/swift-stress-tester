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
  parser.add_argument('--config', default='debug')
  parser.add_argument('--build-dir', default='.build')
  parser.add_argument('--multiroot-data-file', help='Path to an Xcode workspace to create a unified build of SwiftSyntax with other projects.')
  parser.add_argument('--toolchain', required=True, help='the toolchain to use when building this package')
  parser.add_argument('--update', action='store_true', help='update all SwiftPM dependencies')
  parser.add_argument('--no-local-deps', action='store_true', help='use normal remote dependencies when building')
  parser.add_argument('build_actions', help="Extra actions to perform. Can be any number of the following", choices=['all', 'build', 'test', 'install', 'generate-xcodeproj'], nargs="*", default=['build'])

  parsed = parser.parse_args(args)

  if ("install" in parsed.build_actions or "all" in parsed.build_actions) and not parsed.prefix:
    ArgumentParser.error("'--prefix' is required with the install action")
  parsed.swift_exec = os.path.join(parsed.toolchain, 'bin', 'swift')

  parsed.sourcekitd_dir = os.path.join(parsed.toolchain, 'lib')

  # Convert package_dir to absolute path, relative to root of repo.
  repo_path = os.path.dirname(__file__)
  parsed.package_dir = os.path.realpath(
                        os.path.join(repo_path, parsed.package_dir))

  # Convert build_dir to absolute path, relative to package_dir.
  parsed.build_dir = os.path.join(parsed.package_dir, parsed.build_dir)

  return parsed


def run(args):
  package_name = os.path.basename(args.package_dir)

  env = dict(os.environ)
  # Use local dependencies (i.e. checked out next sourcekit-lsp).
  if not args.no_local_deps:
    env['SWIFTCI_USE_LOCAL_DEPS'] = "1"
  env['SWIFT_STRESS_TESTER_SOURCEKIT_SEARCHPATH'] = args.sourcekitd_dir

  if args.update:
    print("** Updating dependencies of %s **" % package_name)
    handle_errors(update_swiftpm_dependencies,
      'Updating dependencies of %s failed' % package_name,
      package_dir=args.package_dir,
      swift_exec=args.swift_exec,
      build_dir=args.build_dir,
      env=env,
      verbose=args.verbose)

  # The test action creates its own build. No need to build if we are just testing
  if should_run_any_action(['build', 'install'], args.build_actions):
    print("** Building %s **" % package_name)
    handle_errors(invoke_swift,
      'Building %s failed' % package_name,
      package_dir=args.package_dir,
      swift_exec=args.swift_exec,
      action='build',
      products=get_products(args.package_dir),
      build_dir=args.build_dir,
      multiroot_data_file=args.multiroot_data_file,
      config=args.config,
      env=env,
      verbose=args.verbose)

  output_dir = os.path.realpath(os.path.join(args.build_dir, args.config))

  if should_run_action("generate-xcodeproj", args.build_actions):
    print("** Generating Xcode project for %s **" % package_name)
    handle_errors(generate_xcodeproj,
      'Generating the Xcode project failed',
      args.package_dir,
      swift_exec=args.swift_exec,
      sourcekit_searchpath=args.sourcekitd_dir,
      env=env,
      verbose=args.verbose)

  if should_run_action("test", args.build_actions):
    print("** Testing %s **" % package_name)
    handle_errors(invoke_swift,
      'Testing %s failed' % package_name,
      package_dir=args.package_dir,
      swift_exec=args.swift_exec,
      action='test',
      products=['%sPackageTests' % package_name],
      build_dir=args.build_dir,
      multiroot_data_file=args.multiroot_data_file,
      config=args.config,
      env=env,
      verbose=args.verbose)

  if should_run_action("install", args.build_actions):
    print("** Installing %s **" % package_name)
    stdlib_dir = os.path.join(args.toolchain, 'lib', 'swift', 'macosx')
    handle_errors(install_package,
      'Installing %s failed' % package_name,
      args.package_dir,
      install_dir=args.prefix,
      sourcekit_searchpath=args.sourcekitd_dir,
      build_dir=output_dir,
      rpaths_to_delete=[stdlib_dir],
      verbose=args.verbose)


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


def handle_errors(func, message, *args, **kwargs):
  try:
    func(*args, **kwargs)
  except subprocess.CalledProcessError as e:
    printerr('FAIL: %s' % message)
    printerr('Executing: %s' % ' '.join(e.cmd))
    sys.exit(1)
  except OSError as e:
    printerr('FAIL: %s' % message)
    printerr('Executing subprocess failed: %s. Add --verbose to see command' % e)
    sys.exit(1)


def update_swiftpm_dependencies(package_dir, swift_exec, build_dir, env, verbose):
  args = [swift_exec, 'package', '--package-path', package_dir, '--build-path', build_dir, 'update']
  check_call(args, env=env, verbose=verbose)


def invoke_swift(package_dir, swift_exec, action, products, build_dir, multiroot_data_file, config, env, verbose):
  # Until rdar://53881101 is implemented, we cannot request a build of multiple
  # targets simultaneously. For now, just build one product after the other.
  for product in products:
    invoke_swift_single_product(package_dir, swift_exec, action, product, build_dir, multiroot_data_file, config, env, verbose)


def invoke_swift_single_product(package_dir, swift_exec, action, product, build_dir, multiroot_data_file, config, env, verbose):
  args = [swift_exec, action, '--package-path', package_dir, '-c', config, '--build-path', build_dir]

  if multiroot_data_file:
    args.extend(['--multiroot-data-file', multiroot_data_file])

  if action == 'test':
    args.extend(['--test-product', product])
  else:
    args.extend(['--product', product])

  # Tell SwiftSyntax that we are building in a build-script environment so that
  # it does not need to rebuilt if it has already been built before.
  env['SWIFT_BUILD_SCRIPT_ENVIRONMENT'] = '1'

  check_call(args, env=env, verbose=verbose)


def install_package(package_dir, install_dir, sourcekit_searchpath, build_dir, rpaths_to_delete, verbose):
  bin_dir = os.path.join(install_dir, 'bin')
  lib_dir = os.path.join(install_dir, 'lib', 'swift', 'macosx')

  for directory in [bin_dir, lib_dir]:
    if not os.path.exists(directory):
      os.makedirs(directory)

  # Install sk-stress-test and sk-swiftc-wrapper
  for product in get_products(package_dir):
    src = os.path.join(build_dir, product)
    dest = os.path.join(bin_dir, product)

    # Create a copy of the list since we modify it
    rpaths_to_delete_for_this_product = list(rpaths_to_delete)
    # Add the rpath to the stdlib in in the toolchain
    rpaths_to_add = ['@executable_path/../lib/swift/macosx']

    if product in ['sk-stress-test', 'swift-evolve']:
      # Make the rpath to sourcekitd relative in the toolchain
      rpaths_to_delete_for_this_product += [sourcekit_searchpath]
      rpaths_to_add += ['@executable_path/../lib']

    install(src, dest,
      rpaths_to_delete=rpaths_to_delete_for_this_product,
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


def generate_xcodeproj(package_dir, swift_exec, sourcekit_searchpath, env, verbose):
  package_name = os.path.basename(package_dir)
  config_path = os.path.join(package_dir, 'Config.xcconfig')
  with open(config_path, 'w') as config_file:
    config_file.write('''
      SYSTEM_FRAMEWORK_SEARCH_PATHS = {sourcekit_searchpath} $(inherited)
      LD_RUNPATH_SEARCH_PATHS = {sourcekit_searchpath} $(inherited)
    '''.format(sourcekit_searchpath=sourcekit_searchpath))

  xcodeproj_path = os.path.join(package_dir, '%s.xcodeproj' % package_name)

  args = [swift_exec, 'package', '--package-path', package_dir, 'generate-xcodeproj', '--xcconfig-overrides', config_path, '--output', xcodeproj_path]
  check_call(args, env=env, verbose=verbose)


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
