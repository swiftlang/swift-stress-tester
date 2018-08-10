# SourceKit Stress Tester

The SourceKit stress tester is a utility for running a range of SourceKit requests at various locations in a set of Swift source files in order to find reproducible crashes in SourceKit. It currently tests the `CursorInfo`, `RangeInfo`, `SemanticRefactoring`, `CodeComplete`, `EditorOpen` and `EditorClose` SourceKit requests, which support a range of editor features like syntax highlighting, code completion, jump-to-definition, live issues, quick help, and refactoring.


## Building

The SourceKit stress tester relies on the SwiftLang library, which isn't included in Xcode's default toolchain, so make sure you have a recent trunk or Swift 4.2 development toolchain installed from [swift.org](https://swift.org/download/). If you install the Swift 4.2 development toolchin be sure to check out `swift-4.2-branch`, rather than `master` in the swift-source-tools repository before continuing with the instructions below.

### Via Xcode

To build using Xcode, you can generate an Xcode project via the command below:

```
$ swift package generate-xcodeproj --xcconfig-overrides Config.xcconfig
```

When you open the generated `SourceKitStressTester.xcodeproj` in Xcode, select the toolchain you installed from the Xcode > Toolchains menu and then build the `SourceKitStressTester-Package` scheme.

### Via swift build
First you'll need to get the get the `CFBundleIdentifier` of the toolchain you installed from its `Info.plist` file at `/Library/Developer/Toolchains/<your-chosen-xctoolchain>/Info.plist` so we can use it to build. It will look something like `org.swift.4220180806a`

You can then build the SourceKit stress tester by substituting it and the path to your chosen xctoolchain's `usr/lib` directory (to find `sourcekitd.framework`) in the command below:

```
$ TOOLCHAIN_LIB=/Library/Developer/Toolchains/<chosen-toolchain>/usr/lib
$ xcrun --toolchain <CFBundleIdentifier> swift build -Xswiftc -Fsystem -Xswiftc $TOOLCHAIN_LIB -Xlinker -rpath -Xlinker $TOOLCHAIN_LIB
```

## Running

However you build, you will end up with two executables: `sk-stress-test` and `sk-swiftc-wrapper`. These will be available in the `.build/debug` directory if building via `swift build`, or under `Products/Debug` in the Xcode project's `DerivedData` directory.

### sk-stress-test
The `sk-stress-test` executable is the SourceKit stress tester itself. It takes as input a set of swift source files to run over, along with the set of driver arguments you would pass to `swiftc` to compile those files, separated by `--`. To stress test sk-stress-test itself for example, we would run:

```
.build/debug/sk-stress-test Sources/StressTester/main.swift -- -sdk `xcrun --show-sdk-path` -Fsystem $TOOLCHAIN_LIB Sources/StressTester/main.swift
```

### sk-swiftc-wrapper
The `sk-swiftc-wrapper` executable allows the stress tester to be easily run on an existing project. It serves as a drop-in replacement for swiftc during a build. When invoked, it simply invokes `swiftc` proper with the same arguments. If the `swiftc` invocation fails, `sk-swiftc-wrapper` will exit with the same exit code. If it succeeds, it additionally invokes `sk-stress-test`, passing it all the Swift files that appeared in its arguments, followed by the arguments themselves. By default it then exits with whatever exit code was returned by `sk-stress-test`, meaning a stress testing failure will cause the build to fail. Specify the `SK_STRESS_SILENT` environment variable to have the wrapper return the same exit code as the `swiftc` invocation, regardless of any stress tester failures.

By default `sk-swiftc-wrapper` invokes the `swiftc` from the toolchain sepcified by the `TOOLCHAINS` environment variable, or the default toolchain of the currently selected Xcode. You can override theis behaviour by setting the `SK_STRESS_SWIFTC` environment variable. Similarly, it looks for `sk-stress-test` adacent to its own launch path, but you can override this by setting the `SK_STRESS_TEST` environment variable.

## Stress testing SourceKit with an existing Xcode project

Since `sk-swiftc-wrapper` works as a drop in replacement for `swiftc`, you can run the stress tester over an existing Xcode project by setting `sk-swiftc-wrapper` as the Swift compiler to use and then building. This is done by adding a user-defined build setting, `SWIFT_EXEC`, to the project or target you would like to stress test, with the path to `sk-swiftc-wrapper` as its value. When you next build, stress testing failures will then manifest in the build log as compilation failures.

