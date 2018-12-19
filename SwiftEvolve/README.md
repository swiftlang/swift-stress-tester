# swift-evolve

This tool randomly permutes Swift source code in ways that should be safe for
resilience. You can then rebuild the dylibs with the modified source, drop them
into an existing binary distribution, and test that nothing breaks.

## Requirements

swift-evolve currently works only with the Swift 5 master branch. It is built with swiftpm
and requires SwiftSyntax.

To set up the appropriate environment:

```
$ mkdir src && cd src
$ brew install cmake ninja
$ git clone https://github.com/apple/swift.git
$ ./swift/utils/update-checkout --clone
```

## Running resilience tests automatically

You can automatically run resilience tests on the standard library with:

```
$ swift-stress-tester/SwiftEvolve/Utility/evolve-swiftCore.sh
```

This performs the following steps:

1. Build Swift, llbuild, SwiftPM, and SwiftSyntax.

2. Run Swift's test suite. **If any tests fail at this point, there is a bug in Swift master which
  has nothing to do with swift-evolve.**

3. Evolve the standard library and generate a diff of the changes.

4. Move the original `lib/swift` folder (containing the generated modules and binaries)
   aside.
    
5. Rebuild Swift with the evolved standard library.

6. Run Swift's test suite, excluding tests known to generate false positives. **If any tests fail
   at this point, there is a source-compatibility bug in Swift or swift-evolve.**

7. Move the evolved `lib/swift` folder aside.

8. Create a new `lib/swift` folder by combining the original modules with the evolved
   binaries.

9. Run Swift's test suite, excluding tests known to generate false positives. **If any tests fail
   at this point, there is a binary-compatibility bug in Swift or swift-evolve.**

## Evolving code manually

To use swift-evolve in another scenario, you can manually build swift-evolve's prerequisites
and run it on code of your choice with these two commands:

```
$ ./swift/utils/build-script --llbuild --swiftpm --swiftsyntax
$ env PATH=$(pwd)/build/Ninja-ReleaseAssert/swiftpm-macosx-x86_64/x86_64-apple-macosx/debug:$PATH \
swift run --package-path swift-stress-tester/SwiftEvolve swift-evolve <args>
```

(The `env` command here ensures you use the right compiler with the package manager
built alongside it; you could instead use a toolchain or some other arrangement.)

The simplest use is to print an evolved version of a source file:

```
$ swift-evolve MyFile.swift
```

("swift-evolve" here is in practice a stand-in for the long `swift run` command above.)

swift-evolve can instead overwrite its inputs with evolved versions:

```
$ swift-evolve --replace MyFile.swift
```

It can take multiple source files:

```
$ swift-evolve --replace MyFile.swift OtherFile.swift
```

And it can take a rules file specifying evolutions which are normally ABI-compatible, but
which should not be performed on this specific codebase:

```
$ swift-evolve --replace --rules excluded.json MyFile.swift OtherFile.swift
```

(See the Utilities/swiftCore-exclude.json file for an example of such a rules file.)

swift-evolve chooses the evolutions it performs randomly. As it runs, it will print new
versions of its command line with a `--seed` or `--plan` parameter. These can be used
to reproduce the same execution of the tool. It also inserts comments into the evolved
source code obliquely describing the evolutions it performed.
