#!/usr/bin/caffeinate -i /bin/bash

until [ -e build ]; do
  if [[ "$(pwd)" == "/" ]]; then
    echo "FAIL: Can't find build directory"
    exit 1
  fi
  cd ..
done

if ! git -C swift diff --exit-code --quiet -- stdlib; then
  git -C swift status stdlib
  echo "FAIL: Unstaged changes in stdlib"
  exit 1
fi

BUILD_SCRIPT_ARGS="--build-subdir=buildbot_evolve-swiftCore" "$@"
ROOT="$(pwd)"
BUILD=$ROOT/build/buildbot_evolve-swiftCore
BUILD_SWIFT=$BUILD/swift-macosx-x86_64
EVOLVE=$ROOT/swift-stress-tester/SwiftEvolve

set -e

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

function buildSwift() {
  assertLibNotSymlink
  run "Building Swift with $phase" swift/utils/build-script $BUILD_SCRIPT_ARGS "$@"
}

function testSwift() {
  run "Testing Swift with $phase" llvm/utils/lit/lit.py -sv --param swift_site_config=$BUILD_SWIFT/test-macosx-x86_64/lit.site.cfg "$@" swift/test
}

function evolveSwift() {
  run "Evolving Swift source code" env PATH="$BUILD/swiftpm-macosx-x86_64/x86_64-apple-macosx/debug:$PATH" swift run --package-path $EVOLVE swift-evolve --replace --rules=$EVOLVE/Utilities/swiftCore-exclude.json $ROOT/swift/stdlib/public/core/*.swift
}

function diffStdlib() {
  git -C swift diff --minimal -- stdlib >$1
}

function libs() {
  echo "$BUILD_SWIFT/lib/swift$1$2"
}

function assertLibNotSymlink() {
  if [ -L $(libs $1 $2) ]; then
    echo "FAILED: Assertion failure: $(libs $1 $2) is a symlink!"
    exit 2
  fi
}

function linkLibs() {
  assertLibNotSymlink $1 $2
  rm -rf $(libs)
  ln -s $(libs $1 $2) $(libs)
}

function saveLibs() {
  rm -rf $(libs $1 $2)
  assertLibNotSymlink
  mv $(libs) $(libs $1 $2)
}

function mixLibs() {
  rm -rf $(libs $1 $2)
  assertLibNotSymlink $1 $1
  run "Copying $1 Modules to $phase" cp -Rc $(libs $1 $1) $(libs $1 $2)
  run "Copying $2 Binaries to $phase" rsync -ai --include '*/' --include '*.dylib' --exclude '*' $(libs $2 $2)/ $(libs $1 $2)
}

phase="Current Modules, Current Binaries"
buildSwift --llbuild --swiftpm --swiftsyntax
testSwift
saveLibs 'Current' 'Current'

evolveSwift
diffStdlib stdlib.diff

phase="Evolved Modules, Evolved Binaries"
buildSwift
testSwift --param swift_evolve
saveLibs 'Evolved' 'Evolved'

phase="Current Modules, Evolved Binaries"
mixLibs 'Current' 'Evolved'
linkLibs 'Current' 'Evolved'
testSwift --param swift_evolve
