<img src="https://swift.org/assets/images/swift.svg" alt="Swift logo" height="70" >

# Swift Stress Tester

This project aims to provide stress testing utilities to help find reproducible crashes and other failures in tools that process Swift source code, such as the Swift compiler and SourceKit. These utilities will ideally be written in Swift and make use the SwiftSyntax and/or SwiftLang libraries to parse, generate and modify Swift source inputs.

## Current tools

| Tool      | Description | build-script Flag | Package Name |
| --------- | ----------- | ----------------- | ----------------- |
[sk&#8209;stress&#8209;test](SourceKitStressTester/README.md) | a utility for exercising a range of SourceKit functionality, such as code completion and local refactorings, at all applicable locations in a set of Swift source files. | `--skstresstester` | SourceKitStressTester |
[swift&#8209;evolve](SwiftEvolve/README.md) | a utility to randomly modify Swift source files in ways libraries are permitted to evolve without breaking ABI compatibility. | `--swiftevolve` | SwiftEvolve |

## Building

The tools in this repository can be built in several different ways:

### Using Swift's build-script

If you want to build the tools to use a locally built sourcekitd and SwiftLang, use the Swift repository's build-script to build and test the stress tester by passing `--skstresstester`, its dependencies and the desired tools' flags as extra options. To build and run tests, for example, you would run:

```
$ ./swift/utils/build-script --test --skip-build-benchmark --skip-test-cmark --skip-test-swift --install-swift --llbuild --install-llbuild --skip-test-llbuild --swiftpm --install-swiftpm --skip-test-swiftpm --skstresstester --swiftevolve --release
```

### For local development

For local development you'll first need to download and install a recent [swift.org development snapshot](https://swift.org/download/#snapshots) toolchain that matches the latest commit on master in the [SwiftSyntax](https://github.com/apple/swift-syntax). This is because the Stress Tester depends on the latest version of SwiftSyntax and SwiftSyntax integrates into the latests version of the compiler.

#### Via Xcode

To generate an Xcode project that's set up correctly, run `build-script-helper.py`, passing the path to the downloaded toolchain via the `--toolchain` option, the tool's package name in the `--package-dir` option, and the `generate-xcodeproj` action:
```
$ ./build-script-helper.py --package-dir SourceKitStressTester --toolchain $TOOLCHAIN_DIR generate-xcodeproj --no-local-deps
```
If you have the [SwiftSyntax](https://github.com/apple/swift-syntax) and [SwiftPM](https://github.com/apple/swift-package-manager) repositories already checked out next to the stress tester's repository, you can omit the `--no-local-deps` option to use the existing checkouts instead of fetching the dependencies using SwiftPM.

This will generate `SourceKitStressTester/SourceKitStressTester.xcodeproj`. Open it and select the toolchain you installed from the Xcode > Toolchains menu, before building the `SourceKitStressTester-Package` scheme.

#### Via command line

To build, run `build-script-helper.py`, passing the path to the downloaded toolchain via the `--toolchain` option and the tool's package name in the `--package-dir` option.
```
$ ./build-script-helper.py --package-dir SourceKitStressTester --toolchain $TOOLCHAIN_DIR
```
If you have the [SwiftSyntax](https://github.com/apple/swift-syntax) and [SwiftPM](https://github.com/apple/swift-package-manager) repositories already checked out next to the stress tester's repository, you can omit the `--no-local-deps` option to use the existing checkouts instead of fetching the dependencies using SwiftPM.

To run the tests, repeat the above command, but additionally pass the `test` action:
```
$ ./Utilities/build-script-helper.py test --package-dir SourceKitStressTester --toolchain $TOOLCHAIN_DIR
```

## Running

Building will create either one or two executables, depending on the package you build. These will be in the package directory's `.build/debug` sudbirectory if building on the command line or via the Swift repo's build-script, and under `Products/Debug` in the Xcode project's `DerivedData` directory if building there. They are also available in the `usr/bin` directory of recent trunk and swift 5.0 development toolchains from swift.org, if you're just interested in running them, rather than building them locally.

See the individual packages' README files for information about how to run and use their executables.

## License

Copyright © 2014 - 2018 Apple Inc. and the Swift project authors.
Licensed under Apache License v2.0 with Runtime Library Exception.

See [http://swift.org/LICENSE.txt](http://swift.org/LICENSE.txt) for license information.
