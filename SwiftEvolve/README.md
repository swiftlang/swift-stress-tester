# swift-evolve

SwiftEvolve simulates a framework engineer evolving a library in backwards-compatible ways by taking Swift source files as input and making random source- and binary-compatible changes to them. It currently shuffles members within type declarations and replaces implicit memberwise initializers with explicit ones.

SwiftEvolve can be used as part of a larger workflow to test Swift's source- and binary-compatibility features. If it is applied to the source code of a library, the modified version should pass all tests the original did; if that library is built with `-enable-resilience`, its dylibs should be usable as drop-in replacements for the original library's. Any failures usually indicate either a bug in the tool or a bug in the language.

SwiftEvolve is not intended to test the library it is run against; rather, it uses that library and its test suite to test the compiler. However, the failures it causes may sometimes indicate that the library is unsafely depending upon compiler implementation details, such as the memory layout of Swift types.

## Building

You can build SwiftEvolve using Swift's build-script, using the command line, or using Xcode. In the latter two cases, you'll use the build-script-helper.py script in the parent directory. Please see [the README file adjacent to it](../README.md) for full instructions.

## Running

However you build, you will end up with an executable called `swift-evolve`. It will be available in the `.build/debug` directory if building on the command line or via the Swift repo's build-script, and under `Products/Debug` in the Xcode project's `DerivedData` directory if building there. It is (or will soon be) also available in the `usr/bin` directory of recent trunk and swift 5.0 development toolchains from swift.org, if you're just interested in running them, rather than building them locally.

### swift-evolve

The `swift-evolve` executable takes one or more Swift source files as input. By default, it generates a random seed, then uses it to select source-compatible evolutions to apply to the files, and finally applies the selected evolutions and prints the resulting source code. As it goes, it prints out modified copies of its command line that can be used to reproduce its changes.

```
$ .build/debug/swift-evolve SourceFile.swift
Planning: .build/debug/swift-evolve --seed=14113475929543082565 /Users/yourname/src/SourceFile.swift
  ...
Evolving: .build/debug/swift-evolve --plan=evolution.plan /Users/yourname/src/SourceFile.swift
  ...
class MyClass {
  deinit { print("in deinit") }
  var myInt: Int
  var myString: String { ... }
  ...
}
...
```

The tool has a number of options; the most important is probably `--replace`, which makes it rewrite files in-place instead of printing the modified versions.

By itself, modifying the source code of a project doesn't do anything; it then needs to be rebuilt and tested in some interesting way:

* Rebuilding the project and running its tests simulates using a new version at both build and runtime.

* Rebuilding the project's implementation (dylibs) but keeping its interface (swiftmodule and other files) unchanged simulates building against an old version but running with a new version.

* Rebuilding the project's interface but keeping its implementation unchanged simulates building against a new version but running with an old version.

The `swift-evolve` tool is meant to be used as one step in a larger process which rebuilds and possibly mixes files to create these configurations. Rebuilding, mixing, and testing can be done by hand, or it can be automated using a script. The `Utility/evolve-swiftCore.sh` script in this repository is one such example.

`swift-evolve` does not make the same changes every time it's run, so it's best to evolve and test, then restore the source files to their original state and repeat until satisfied there's nothing left to shake out.

### Utility/evolve-swiftCore.sh

This script automates resilience testing using the Swift standard library and lit test suite. Specifically, it performs the following steps:

1. Builds the current Swift and SwiftEvolve, then tests Swift.
2. Evolves the Swift standard library, then re-tests Swift.
3. Mixes the current interface files with the evolved implementation files, then re-tests Swift.

Any build or test failures indicate a bug in either SwiftEvolve or the Swift compiler; depending on the step it's in, you can tell which kind of bug it found:

1. A bug in the basic functionality of Swift; normal builds should show the same issues.
2. A bug in the source stability of Swift or SwiftEvolve's evolutions.
3. A bug in the ABI stability of Swift or SwiftEvolve's evolutions.

The script also captures standard library diffs and other information which might be useful to reproduce any failures.

Some parts of the standard library are tied to private implementation details of the compiler or runtime; evolving these in certain ways may cause spurious failures. The `swiftCore-exclude.json` specifies these declarations and the evolutions that are expected to break them so that `swift-evolve` can avoid causing these issues.

When running Swift's test suite in steps 2 or 3, the script turns on the "swift_evolve" feature in `lit`. This feature is used to disable tests which are known to sometimes fail during swift-evolve testing, either due to expected behavor or due to known but unfixed bugs. When a test is known to sometimes fail during swift-evolve testing, you should add `// UNSUPPORTED: swift_evolve` to its file.
