# SourceKit Stress Tester

The SourceKit stress tester is a utility for running a range of SourceKit queries at various locations in an existing project in order to find reproducible crashes and failures in SourceKit. It currently supports the `CursorInfo`, `RangeInfo`, `SemanticRefactoring`, and `CodeComplete` SourceKit requests.

TODO: explanation of sk-stress-test and sk-swiftc-wrapper

## Building
Make sure you have a recent trunk or Swift 4.2 development toolchain installed from [swift.org](https://swift.org/download/) that includes the SwiftLang library. You can check for it at: 

```
/Library/Developer/Toolchains/<your-chosen-xctoolchain>/usr/lib/swift/macosx/libswiftSwiftLang.dylib
```

### Via swift build
First you'll need to get the get the `CFBundleIdentifier` of the toolchain you installed from its `Info.plist` file at `/Library/Developer/Toolchains/<your-chosen-xctoolchain>/Info.plist`. It will look something like `org.swift.4220180611a`

You can then build the SourceKit stress tester by substituting it and your chosen xctoolchain in the command below:

```
$ TOOLCHAINS=<CFBundleIdentifier> swift build -Xswiftc -target -Xswiftc x86_64-apple-macosx10.13 -Xswiftc -Fsystem -Xswiftc /Library/Developer/Toolchains/<your-chosen-xctoolchain>/usr/lib -Xlinker -rpath -Xlinker /Library/Developer/Toolchains/<your-chosen-xctoolchain>/usr/lib
```
The `sk-stress-test` and `sk-swiftc-wrapper` exectuables will then be available in `.build/debug`. You can add  `-c release` to the command above for a release build.

### Via Xcode

First, generate the corresponding Xcode project via the command below:

```
$ swift package generate-xcodeproj --xcconfig-overrides Config.xcconfig
> generated: ./SourceKitStressTester.xcodeproj
```

When you open the generated Xcode project, select the toolchain you installed in the Xcode > Toolchains menu and then build the `SourceKitStressTester-Package` scheme.

## Running

TODO: give an example of how to use it to stress test an existing Xcode project and swiftpm package.

Set `SWIFT_EXEC` to point to the wrapper
Set `SK_STRESS_SWIFTC` to point to the swiftc to use for the underlying build (if you don't set it, the wrapper will use the selected Xcode's swiftc) 
Set `SK_STRESS_SILENT` to not fail the sk-swiftc-wrapper invocation if the underlying swiftc invocation succeeded but sk-stress-test detected an issue. Stress tester failures will still appear in the build log, but the build will still succeed if the wrapped swiftc invocation succeeded.

