#!/usr/bin/env bash

cd $(dirname $0)/..
swift package clean
SWIFT_STRESS_TESTER_SOURCEKIT_SEARCHPATH=/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/lib/ swift build
sudo ln -s ./.build/debug/sk-swiftc-wrapper /Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/ || true
sudo ln -s ./.build/debug/sk-stress-test /Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/ || true
