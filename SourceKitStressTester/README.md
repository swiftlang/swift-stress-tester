# Sourcekitd Stress Tester

The Sourcekitd stress tester is a utility for running a range of sourcekitd requests at various locations in a set of Swift source files in order to find reproducible crashes in sourcekitd. It currently tests the `CursorInfo`, `RangeInfo`, `SemanticRefactoring`, `CodeComplete`, `EditorOpen` and `EditorClose` sourcekitd requests, which support a range of editor features like syntax highlighting, code completion, jump-to-definition, live issues, quick help, and refactoring.


## Building

The sourcekitd stress tester relies on the SwiftLang library, which isn't included in Xcode's default toolchain, so make sure you have a recent trunk or Swift 5.0 development toolchain installed from [swift.org](https://swift.org/download/). 

Also take note of where the toolchain you installed is located. Depending on the options you chose this should be under Library/Developer/Toolchains/<downloaded-toolchain> in either you home or root directory, e.g:
```
$ TOOLCHAIN_DIR=/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2018-11-26-a.xctoolchain
```

### Workspace setup
For local development you'll need to have the [Swift](https://github.com/apple/swift) and [SwiftSyntax](https://github.com/apple/swift-syntax) repositories checked out adjacent to the swift-stress-tester repository in the structure shown below:
```
<workspace>/
  swift/
  swift-syntax/
  swift-stress-tester/
```
If you installed the Swift 5.0 development toolchain be sure to check out `swift-5.0-branch`, rather than `master` in all of these repositories before continuing with the instructions below.

### Via Xcode

To generate an Xcode project that's set up correctly, run `build-script-helper.py` in the Utilities directory, passing the path to the swiftc executable in the downloaded toolchain via the `--swiftc-exec` option and the `generate-xcodeproj` action:
```
$ ./Utilities/build-script-helper.py --swiftc-exec $TOOLCHAIN_DIR/usr/bin/swiftc generate-xcodeproj
```
This will generate `SourceKitStressTester.xcodeproj`. Open it and select the toolchain you installed from the Xcode > Toolchains menu, before building the `SourceKitStressTester-Package` scheme.

### Via command line

To build, run `build-script-helper.py` in the Utilities directory, passing the path to the swiftc executable in the downloaded toolchain via the `--swiftc-exec` option:
```
$ ./Utilities/build-script-helper.py --swiftc-exec $TOOLCHAIN_DIR/usr/bin/swiftc
```

To run the tests, repeat the above command, but additionally pass the `test` action:
```
$ ./Utilities/build-script-helper.py --swiftc-exec $TOOLCHAIN_DIR/usr/bin/swiftc test
```

### Via swift's build script

If you want to build the stress tester to use a locally built sourcekitd and SwiftLang, use the Swift repository's build-script to build and test the stress tester by passing `--swiftsyntax` and `--skstresstester` as extra options. To build and run tests, for example, you would run:
```
$ ./utils/build-script -t --swiftsyntax --skstresstester
```

## Running

However you build, you will end up with two executables: `sk-stress-test` and `sk-swiftc-wrapper`. These will be available in the `.build/debug` directory if building on the command line or via the Swift repo's build-script, and under `Products/Debug` in the Xcode project's `DerivedData` directory if building there. They are also available in the `usr/bin` directory of recent trunk and swift 5.0 development toolchains from swift.org, if you're just interested in running them, rather than building them locally.

### sk-stress-test
The `sk-stress-test` executable is the sourcekitd stress tester itself. It takes as input a swift source file to run over, along with the set of driver arguments you would pass to `swiftc` to compile those files. Here is a simple example invocation:

```
$ echo 'print("hello")' > /tmp/test.swift
$ .build/debug/sk-stress-test /tmp/test.swift swiftc /tmp/test.swift
```

### sk-swiftc-wrapper
The `sk-swiftc-wrapper` executable allows the stress tester to be easily run on an existing project. It serves as a drop-in replacement for `swiftc` during a build. When invoked, it simply invokes `swiftc` proper with the same arguments. If the `swiftc` invocation fails, `sk-swiftc-wrapper` will exit with the same exit code. If it succeeds, it additionally invokes `sk-stress-test` for each Swift file that appears in its arguments, followed by the arguments themselves. By default it then exits with whatever exit code was returned by `sk-stress-test`, meaning a stress testing failure will cause the build to fail. Specify the `SK_STRESS_SILENT` environment variable to have the wrapper return the same exit code as the `swiftc` invocation, regardless of any stress tester failures. Here is an example invocation:
```
$ echo 'print("hello")' > /tmp/test.swift
$ .build/debug/sk-swiftc-wrapper /tmp/test.swift
```

By default `sk-swiftc-wrapper` invokes the `swiftc` from the toolchain specified by the `TOOLCHAINS` environment variable, or the default toolchain of the currently `xcode-select`ed Xcode. You can override this behaviour by setting the `SK_STRESS_SWIFTC` environment variable. Similarly, it looks for `sk-stress-test` adjacent to its own launch path, but you can override this by setting the `SK_STRESS_TEST` environment variable.

## Stress testing sourcekitd with an existing Xcode project

Since `sk-swiftc-wrapper` works as a drop in replacement for `swiftc`, you can run the stress tester over an existing Xcode project by setting `sk-swiftc-wrapper` as the Swift compiler to use and then building. This is done by adding a user-defined build setting, `SWIFT_EXEC`, to the project or target you would like to stress test, with the path to `sk-swiftc-wrapper` as its value. When you next build, stress testing failures will then manifest in the build output as compilation failures.

## Stress testing sourcekitd with a Swift package manager project

For Swift package manager projects, you can stress test sourcekitd by setting the `SWIFT_EXEC` environment variable to point to `sk-swiftc-wrapper` and building as normal. For projects without any custom flags, this is as simple as running:
```
SWIFT_EXEC=/path/to/sk-swiftc-wrapper swift build
```
in the directory with the package manifest file.

