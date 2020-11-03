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

  @Option(name: .shortAndLong, help: """
    One of '\(RequestSet.all.valueNames.joined(separator: "\", \""))', \"IDE\",
    or \"All\"
    """)
  public var request: [RequestSet] = [.ide]

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

  @Argument(help: "A Swift source file to stress test", completion: .file(),
            transform: URL.init(fileURLWithPath:))
  public var file: URL

  @Argument(help: "Swift compiler arguments for the provided file")
  public var compilerArgs: [String]

  public init() {}

  public mutating func validate() throws {
    guard FileManager.default.fileExists(atPath: file.path) else {
      throw ValidationError("File does not exist at \(file.path)")
    }
  }

  public func run() throws {
    let options = StressTesterOptions(
      astBuildLimit: limit,
      requests: request.reduce([]) { result, next in
        result.union(next)
      },
      rewriteMode: rewriteMode,
      conformingMethodsTypeList: conformingMethodsTypeList,
      responseHandler: !reportResponses ? nil :
        { [format] responseData in
          try StressTesterTool.report(
            StressTesterMessage.produced(responseData),
            as: format)
        },
      page: page)

    do {
      let tester = StressTester(for: file, compilerArgs: compilerArgs,
                                options: options)
      if dryRun {
        let tree = try SyntaxParser.parse(file)
        try StressTesterTool.report(
          tester.computeStartStateAndActions(from: tree).actions,
          as: format)
      } else {
        try tester.run()
      }
    } catch let error as SourceKitError {
      let message = StressTesterMessage.detected(error)
      try StressTesterTool.report(message, as: format)
      throw ExitCode.failure
    }
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

extension RequestSet: ExpressibleByArgument {
  public init?(argument: String) {
    switch argument.lowercased() {
    case "format":
      self = .format
    case "cursorinfo":
      self = .cursorInfo
    case "rangeinfo":
      self = .rangeInfo
    case "codecomplete":
      self = .codeComplete
    case "typecontextinfo":
      self = .typeContextInfo
    case "conformingmethodlist":
      self = .conformingMethodList
    case "collectexpressiontype":
      self = .collectExpressionType
    case "all":
      self = .all
    default:
      return nil
    }
  }
}

extension RewriteMode: ExpressibleByArgument {}
