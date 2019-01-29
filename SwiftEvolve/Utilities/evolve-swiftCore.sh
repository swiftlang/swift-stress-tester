#!/usr/bin/caffeinate -i /bin/bash

#
# Script to run resilience tests against the Swift standard library.
#
# This is meant to be a temporary driver while we're figuring out the right
# logic, but we all know that temporary things don't stay that way, so if you're
# reading this comment in 2020 feel free to laugh at me.
#

# cd up until we find the directory containing all projects.
until [ -e swift-stress-tester ]; do
  if [[ "$(pwd)" == "/" ]]; then
    echo "FAIL: Can't find root directory"
    exit 1
  fi
  cd ..
done

# Make sure we don't have stdlib changes from a previous run.
if ! git -C swift diff --exit-code --quiet -- stdlib; then
  git -C swift status stdlib
  echo "FAIL: Unstaged changes in stdlib"
  echo "      (To clear them, run 'git -C swift checkout HEAD -- stdlib')"
  exit 1
fi

# Set up a few globals.
ITERATIONS="${1-1}"
BUILD_SCRIPT_ARGS="--build-subdir=buildbot_evolve-swiftCore --release"
ROOT="$(pwd)"
BUILD=$ROOT/build/buildbot_evolve-swiftCore
BUILD_SWIFT=$BUILD/swift-macosx-x86_64
EVOLVE=$ROOT/swift-stress-tester/SwiftEvolve

set -e

#
# HELPERS
#

# Make sure we don't have stdlib changes from a previous run.
function resetStdlib() {
  git -C swift checkout HEAD -- stdlib
}

# Run a command with pass/fail messages.
function run() {
  descString="$1"
  shift 1

  echo "BEGIN: $descString"
  echo '$' "$@"
  if "$@" ; then
    echo "PASS: $descString"
  else
    echo "FAIL: $descString"
    exit 1
  fi
}

# Run utils/build-script with the provided arguments.
function buildSwift() {
  assertLibNotSymlink
  run "Building Swift with $phase" swift/utils/build-script $BUILD_SCRIPT_ARGS "$@"
}

# Run lit tests with the provided arguments.
function testSwift() {
  run "Testing Swift with $phase" llvm/utils/lit/lit.py -sv --param swift_site_config=$BUILD_SWIFT/test-macosx-x86_64/lit.site.cfg "$@" swift/test
}

# Modify swift/stdlib source code.
function evolveStdlib() {
  # Temporarily re-link lib/swift to lib/swiftCurrentCurrent
  linkLibs Current Current
  run "Evolving Swift source code" env SWIFT_EXEC="$BUILD_SWIFT/bin/swiftc" $BUILD/swiftevolve-macosx-x86_64/release/swift-evolve --replace --rules=$EVOLVE/Utilities/swiftCore-exclude.json $ROOT/swift/stdlib/public/core/*.swift
  rm $(libs)
}

# Generate a diff of swift/stdlib.
function diffStdlib() {
  git -C swift diff --minimal -- stdlib >$1
}

# Returns the path to a built lib/swift folder. If provided, $1 should be the
# interfaces (Current/Evolved) and $2 should be the implementations
# (Current/Evolved)
function libs() {
  echo "$BUILD_SWIFT/lib/swift$1$2"
}

# Exits if the indicated directory is a symbolic link; this would indicate the
# build folder is in a dirty, previously modified state.
function assertLibNotSymlink() {
  if [ -L $(libs $1 $2) ]; then
    echo "FAIL: Assertion failure: $(libs $1 $2) is a symlink!"
    exit 2
  fi
}

# Change lib/swift to link to the indicated lib/swift folder.
function linkLibs() {
  assertLibNotSymlink $1 $2
  rm -rf $(libs)
  ln -s $(libs $1 $2) $(libs)
}

# Move lib/swift to the indicated folder.
function saveLibs() {
  rm -rf $(libs $1 $2)
  assertLibNotSymlink
  mv $(libs) $(libs $1 $2)
}

# Combine the interfaces from $1 with the implementations from $2.
function mixLibs() {
  rm -rf $(libs $1 $2)
  assertLibNotSymlink $1 $1
  run "Copying $1 Modules to $phase" cp -Rc $(libs $1 $1) $(libs $1 $2)
  run "Copying $2 Binaries to $phase" rsync -ai --include '*/' --include '*.dylib' --exclude '*' $(libs $2 $2)/ $(libs $1 $2)
}

#
# MAIN FLOW
#

# Build and test a stock version of Swift.
phase="Current Modules, Current Binaries"

buildSwift --swiftsyntax --swiftevolve
testSwift
saveLibs 'Current' 'Current'

for iteration in $(seq $ITERATIONS); do
  phase="Evolving ($iteration)"

  # Modify the standard library.
  resetStdlib
  evolveStdlib
  diffStdlib "stdlib-$iteration.diff"

  # Build and test a version of Swift with the evolved libraries, then move them
  # to lib/swiftEvolvedEvolved.
  phase="Evolved Modules, Evolved Binaries ($iteration)"
  buildSwift
  testSwift --param swift_evolve
  saveLibs "Evolved$iteration" "Evolved$iteration"

  # Combine the Current interfaces with the Evolved implementations, then test
  # the combination.
  phase="Current Modules, Evolved Binaries ($iteration)"
  mixLibs 'Current' "Evolved$iteration"
  linkLibs 'Current' "Evolved$iteration"
  testSwift --param swift_evolve
done
