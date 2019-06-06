# Sourcekitd Stress Tester

The Sourcekitd stress tester is a utility for running a range of sourcekitd requests at various locations in a set of Swift source files in order to find reproducible crashes in sourcekitd. It currently tests the `CursorInfo`, `RangeInfo`, `SemanticRefactoring`, `CodeComplete`, `TypeContextInfo`, `ConformingMethodList`, `CollectExpressionType`, `EditorOpen` and `EditorClose` sourcekitd requests, which support a range of editor features like syntax highlighting, code completion, jump-to-definition, live issues, quick help, and refactoring.


## Building

You can build SourceKitStressTester using Swift's build-script, using the command line, or using Xcode. In the latter two cases, you'll use the build-script-helper.py script in the parent directory. Please see [the README file adjacent to it](../README.md) for full instructions.

## Running

However you build, you will end up with two executables: `sk-stress-test` and `sk-swiftc-wrapper`. These will be available in the `.build/debug` directory if building on the command line or via the Swift repo's build-script, and under `Products/Debug` in the Xcode project's `DerivedData` directory if building there. They are also available in the `usr/bin` directory of recent trunk and swift 5.1 development toolchains from swift.org, if you're just interested in running them, rather than building them locally.

### sk-stress-test
The `sk-stress-test` executable is the sourcekitd stress tester itself. It takes as input a swift source file to run over, along with the set of driver arguments you would pass to `swiftc` to compile those files. Here is a simple example invocation:

```
$ echo 'print("hello")' > /tmp/test.swift
$ .build/debug/sk-stress-test /tmp/test.swift swiftc /tmp/test.swift
```

For a description of the available options see `sk-stress-test`'s help output:

```
$ .build/debug/sk-stress-test --help
```

### sk-swiftc-wrapper
The `sk-swiftc-wrapper` executable allows the stress tester to be easily run on an existing project. It serves as a drop-in replacement for `swiftc` during a build. When invoked, it simply invokes `swiftc` proper with the same arguments. If the `swiftc` invocation fails, `sk-swiftc-wrapper` will exit with the same exit code. If it succeeds, it additionally invokes `sk-stress-test` for each Swift file that appears in its arguments, followed by the arguments themselves. By default it then exits with whatever exit code was returned by `sk-stress-test`, meaning a stress testing failure will cause the build to fail. Specify the `SK_STRESS_SILENT` environment variable to have the wrapper return the same exit code as the `swiftc` invocation, regardless of any stress tester failures. Here is an example invocation:
```
$ echo 'print("hello")' > /tmp/test.swift
$ .build/debug/sk-swiftc-wrapper /tmp/test.swift
```

By default `sk-swiftc-wrapper` invokes the `swiftc` from the toolchain specified by the `TOOLCHAINS` environment variable, or the default toolchain of the currently `xcode-select`ed Xcode. You can override this behaviour by setting the `SK_STRESS_SWIFTC` environment variable. Similarly, it looks for `sk-stress-test` adjacent to its own launch path, but you can override this by setting the `SK_STRESS_TEST` environment variable.

Other evironment variable you can use to change its default behaviour include:

Environment variable and example value | Description
------------ | -------------
SK_STRESS_REWRITE_MODES='none basic insideOut' | A space-separated list of `--rewrite-mode` strategies to use.
SK_STRESS_REQUESTS='CursorInfo CodeCompletion' | A space-separated list of requests to stress test.
SK_STRESS_CONFORMING_METHOD_TYPES='s:SQ' | A space-separated list of the USRs of the conformed-to symbols to use in the `ConformingMethodList` request. You can get the USR of a symbol by looking at a `CursorInfo` response invoked on an occurrence of that symbol.
SK_STRESS_MAX_JOBS=4 | The maximum number of concurrent `sk-stress-test` invocations to make.
SK_STRESS_AST_BUILD_LIMIT=2000 | The maximum number of sourcekitd requests that trigger AST builds to allow per file.
SK_STRESS_OUTPUT=/tmp/results.json | A file path to dump the stress testing results to (JSON format).
SK_XFAILS_PATH=/tmp/xfails.json | The path to a JSON file that can be used to report particular detected failures as expected. Whenever an unexpected failure is detected, an example entry you can add to this file to mark it as expected will be produced.
SK_STRESS_ACTIVE_CONFIG=master | Entries in the SK_XFAILS_PATH file can include a list of applicable configurations. This variable indicates which configuration the current run represents, and will determine the subset of XFAIL entries that apply to this run.
SK_STRESS_SUPPRESS_OUTPUT=1 | By default `sk-swiftc-wrapper` outputs progress and detected failures on stderr, as additional output on top of what the wrapper swiftc produced. Set this variable true to prevent this additional output. Results will still be output to the path specified by SK_STRESS_OUPUT.
SK_STRESS_DUMP_RESPONSES_PATH=/tmp/responses.txt | If specified, all responses received from sourcekitd during stress testing will be written out to the provided path. This is useful for comparing the responses produced from different versions of sourcekitd. Note: to reduce file size, if a response is identical to one produced previously in the same run, a reference to the earlier response will be output instead.


## Stress testing sourcekitd with an existing Xcode project

Since `sk-swiftc-wrapper` works as a drop in replacement for `swiftc`, you can run the stress tester over an existing Xcode project by setting `sk-swiftc-wrapper` as the Swift compiler to use and then building. This is done by adding a user-defined build setting, `SWIFT_EXEC`, to the project or target you would like to stress test, with the path to `sk-swiftc-wrapper` as its value. When you next build, stress testing failures will then manifest in the build output as compilation failures.

## Stress testing sourcekitd with a Swift package manager project

For Swift package manager projects, you can stress test sourcekitd by setting the `SWIFT_EXEC` environment variable to point to `sk-swiftc-wrapper` and building as normal. For projects without any custom flags, this is as simple as running:
```
SWIFT_EXEC=/path/to/sk-swiftc-wrapper swift build
```
in the directory with the package manifest file.

