<img src="https://swift.org/assets/images/swift.svg" alt="Swift logo" height="70" >

# Swift Stress Tester

This project aims to provide stress testing utilities to help find reproducible crashes and other failures in tools that process Swift source code, such as the Swift compiler and SourceKit. These utilities will ideally be written in Swift and make use the SwiftSyntax and SwiftLang libraries to parse, generate and modify Swift source inputs.

## Current tools

| Tool      | Description |
| --------- | ----------- |
[sk&#8209;stress&#8209;test](SourceKitStressTester/README.md) | a utility for exercising a range of SourceKit functionality, such as code completion and local refactorings, at all applicable locations in a set of Swift source files.
[swift&#8209;evolve](SwiftEvolve/README.md) | a utility to randomly modify Swift source files in ways libraries are permitted to evolve without breaking ABI compatibility.

## License

Copyright © 2014 - 2018 Apple Inc. and the Swift project authors.
Licensed under Apache License v2.0 with Runtime Library Exception.

See [http://swift.org/LICENSE.txt](http://swift.org/LICENSE.txt) for license information.
