//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Foundation
import Common
import SwiftSyntax

public struct StressTesterTool: ParsableCommand {
  public static var configuration = CommandConfiguration(
    abstract: "A utility for finding sourcekitd crashes in a Swift source file"
  )

  @Option(name: [.long, .customShort("m")], help: """
    One of 'none' (default), 'basic', 'concurrent', 'insideOut', or 'typoed'
    """)
  public var rewriteMode: RewriteMode = .none

  @Option(name: .shortAndLong, help: """
    Format of results. Either 'json' or 'humanReadable'
    """)
  public var format: OutputFormat = .humanReadable

  @Option(name: .shortAndLong, help: ArgumentHelp("""
    The maximum number of AST builds (triggered by CodeComplete, \
    TypeContextInfo, ConformingMethodList and file modifications) to \
    allow per file
    """, valueName: "n"))
  public var limit: Int?

  @Option(name: .shortAndLong, help: ArgumentHelp("""
    Divides the work for each file into <total> equal parts \
    and only performs the <page>th group.
    """, valueName: "page/total"))
  public var page: Page = Page()

  @Option(name: [.customLong("request"), .customShort("r")],
          help: "One of '\(RequestKind.allCases.map({ $0.rawValue }).joined(separator: "\", \""))'")
  public var requests: [RequestKind] = [.ide]

  @Flag(name: .shortAndLong, help: """
    Dump the sourcekitd requests the stress tester would perform instead of \
    performing them
    """)
  public var dryRun: Bool = false

  @Flag(name: .long, help: """
    Output sourcekitd's response to each request the stress tester makes
    """)
  public var reportResponses: Bool = false

  @Option(name: [.customLong("type-list-item"), .customShort("t")], help: """
    The USR of a conformed-to protocol to use for the ConformingMethodList \
    request
    """)
  public var conformingMethodsTypeList: [String] = ["s:SQ", "s:SH"] // Equatable and Hashable

  @Option(name: .long,
          help: "Path to a temporary directory to store intermediate modules",
          transform: URL.init(fileURLWithPath:))
  public var tempDir: URL?

  @Option(name: .shortAndLong, help: """
    Path of swiftc to run, defaults to retrieving from xcrun if not given
    """)
  public var swiftc: String?

  @Argument(help: "A Swift source file to stress test", completion: .file(),
            transform: URL.init(fileURLWithPath:))
  public var file: URL

  @Argument(help: "Swift compiler arguments for the provided file")
  public var compilerArgs: [CompilerArg]

  public init() {}

  private mutating func customValidate() throws {
    let hasFileCompilerArg = compilerArgs.contains { arg in
      arg.transformed.contains { $0 == file.path }
    }
    if !hasFileCompilerArg {
      throw ValidationError("\(file.path) missing from compiler args")
    }

    guard FileManager.default.fileExists(atPath: file.path) else {
      throw ValidationError("File does not exist at \(file.path)")
    }

    if swiftc == nil {
      swiftc = pathFromXcrun(for: "swiftc")
    }
    guard let swiftc = swiftc else {
      throw ValidationError("No swiftc given and no default could be determined")
    }
    guard FileManager.default.isExecutableFile(atPath: swiftc) else {
      throw ValidationError("swiftc at '\(swiftc)' is not executable")
    }

    if tempDir == nil {
      do {
        tempDir = try FileManager.default.url(
          for: .itemReplacementDirectory,
          in: .userDomainMask,
          appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
          create: true)
      } catch let error {
        throw ValidationError("Could not create temporary directory: \(error.localizedDescription)")
      }
    } else if !FileManager.default.fileExists(atPath: tempDir!.path) {
      throw ValidationError("Temporary directory \(tempDir!.path) does not exist")
    }
  }

  public mutating func run() throws {
    // FIXME: Remove this and rename `customValidate` to `validate` once swift
    // is using an argument parser with c17e00a (ie. keeping mutations in
    // `validate`).
    try customValidate()

    let options = StressTesterOptions(
      requests: RequestKind.reduce(requests),
      rewriteMode: rewriteMode,
      conformingMethodsTypeList: conformingMethodsTypeList,
      page: page,
      tempDir: tempDir!,
      astBuildLimit: limit,
      responseHandler: !reportResponses ? nil :
        { [format] responseData in
          try StressTesterTool.report(
            StressTesterMessage.produced(responseData),
            as: format)
        },
      dryRun: !dryRun ? nil :
        { [format] actions in
          for action in actions {
            try StressTesterTool.report(action, as: format)
          }
        }
    )

    do {
      let processedArgs = CompilerArgs(for: file,
                                       args: compilerArgs,
                                       tempDir: tempDir!)
      let tester = StressTester(options: options)
      try tester.run(swiftc: swiftc!, compilerArgs: processedArgs)
    } catch let error as SourceKitError {
      let message = StressTesterMessage.detected(error)
      try StressTesterTool.report(message, as: format)
      throw ExitCode.failure
    }

    // Leave for debugging purposes if there was an error
    try FileManager.default.removeItem(at: tempDir!)
  }

  private static func report<T>(_ message: T, as format: OutputFormat) throws
  where T: Codable & CustomStringConvertible {
    switch format {
    case .humanReadable:
      print(String(describing: message))
    case .json:
      let data = try JSONEncoder().encode(message)
      print(String(data: data, encoding: .utf8)!)
    }
  }
}

public enum OutputFormat: String, ExpressibleByArgument {
  case humanReadable
  case json
}

extension Page: ExpressibleByArgument {
  public init?(argument: String) {
    let parts = argument.split(separator: "/", maxSplits: 1,
                               omittingEmptySubsequences: false)
    if parts.count == 2 {
      if let number = Int(parts[0]),
         let count = Int(parts[1]), number > 0,
         number <= count {
        self.init(number, of: count)
        return
      }
    }
    return nil
  }
}

extension RequestKind: ExpressibleByArgument {
  public init?(argument: String) {
    guard let kind = RequestKind.byName(argument) else {
      return nil
    }
    self = kind
  }
}

extension RewriteMode: ExpressibleByArgument {}

extension CompilerArg : ExpressibleByArgument {
  public init(argument: String) {
    self.init(argument)
  }
}
