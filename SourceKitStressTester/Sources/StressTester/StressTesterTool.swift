//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import Common
import TSCUtility
import TSCBasic
import SwiftSyntax

public struct StressTesterTool {
  let parser: ArgumentParser
  let arguments: [String]

  let usage = "<options> <source-file> swiftc <swiftc-args>"
  let overview = "A utility for finding sourcekitd crashes in a Swift source file"

  /// Arguments
  let mode: OptionArgument<RewriteMode>
  let format: OptionArgument<OutputFormat>
  let limit: OptionArgument<Int>
  let page: OptionArgument<Page>
  let request: OptionArgument<[RequestSet]>
  let dryRun: OptionArgument<Bool>
  let reportResponses: OptionArgument<Bool>
  let conformingMethodsTypeList: OptionArgument<[String]>
  let file: PositionalArgument<PathArgument>
  let compilerArgs: PositionalArgument<[String]>

  public init(arguments: [String]) {
    self.arguments = Array(arguments.dropFirst())

    self.parser = ArgumentParser(usage: usage, overview: overview)
    mode = parser.add(
      option: "--rewrite-mode", shortName: "-m", kind: RewriteMode.self,
      usage: "<MODE> One of 'none' (default), 'basic', 'concurrent', 'insideOut', or 'typoed'")
    format = parser.add(
      option: "--format", shortName: "-f", kind: OutputFormat.self,
      usage: "<FORMAT> One of 'json' or 'humanReadable'")
    limit = parser.add(
      option: "--limit", shortName: "-l", kind: Int.self,
      usage: "<N> The maximum number of AST builds (triggered by CodeComplete, TypeContextInfo, ConformingMethodList and file modifications) to allow per file")
    page = parser.add(
      option: "--page", shortName: "-p", kind: Page.self,
      usage: "<PAGE>/<TOTAL> Divides the work for each file into <TOTAL> equal parts" +
      " and only performs the <PAGE>th group.")
    request = parser.add(
      option: "--request", shortName: "-r", kind: [RequestSet].self, strategy: .oneByOne,
      usage: "<REQUEST> One of '\(RequestSet.all.valueNames.joined(separator: "', '"))', or 'All'")
    dryRun = parser.add(
      option: "--dryrun", shortName: "-d", kind: Bool.self,
      usage: "Dump the sourcekitd requests the stress tester would perform instead of performing them")
    reportResponses = parser.add(
      option: "--report-responses", kind: Bool.self,
      usage: "Output sourcekitd's response to each request the stress tester makes")
    conformingMethodsTypeList = parser.add(
      option: "--type-list-item", shortName: "-t", kind: [String].self, strategy: .oneByOne,
      usage: "The USR of a conformed-to protocol to use for the ConformingMethodList request")
    file = parser.add(
      positional: "<source-file>", kind: PathArgument.self, optional: false,
      usage: "A Swift source file to stress test", completion: .filename)

    // Note: the required 'swiftc' is to workaround ArgumentParser treating a
    // compiler option in the first position as something it should parse as an
    // option. There is no support for '--' to separate positionals at present.
    compilerArgs = parser.add(
      positional: "swiftc <compiler-args>", kind: [String].self, strategy: .remaining,
      usage: "swift compiler arguments for the provided file")

  }

  public func run() throws -> Bool {
    let results = try parse()
    return try process(results)
  }

  public func parse() throws -> ArgumentParser.Result {
    let result = try parser.parse(arguments)

    // validate arguments
    guard let args = result.get(compilerArgs), let first = args.first, first == "swiftc" else {
      throw ArgumentParserError.invalidValue(argument: "swiftc <compiler-args>",
                                             error: ArgumentConversionError.custom("missing 'swiftc' keyword"))
    }
    guard args.count > 1 else {
      throw ArgumentParserError.expectedArguments(parser, ["swiftc <compiler-args>"])
    }

    return result
  }

  private func process(_ arguments: ArgumentParser.Result) throws -> Bool {
    var options = StressTesterOptions()
    if let mode = arguments.get(mode) {
      options.rewriteMode = mode
    }
    if let limit = arguments.get(limit) {
      options.astBuildLimit = limit
    }
    if let page = arguments.get(page) {
      options.page = page
    }
    if let requests = arguments.get(request) {
      options.requests = requests.reduce([]) { result, next in result.union(next) }
    }
    if let typeList = arguments.get(conformingMethodsTypeList) {
      options.conformingMethodsTypeList = typeList
    }

    let format = arguments.get(self.format) ?? .humanReadable
    let dryRun = arguments.get(self.dryRun) ?? false

    if let reportResponses = arguments.get(self.reportResponses), reportResponses {
      options.responseHandler = { responseData in
        try self.report(StressTesterMessage.produced(responseData), as: format)
      }
    }

    let absoluteFile = URL(fileURLWithPath: arguments.get(file)!.path.pathString)
    let args = Array(arguments.get(compilerArgs)!.dropFirst())

    do {
      let tester = StressTester(for: absoluteFile, compilerArgs: args, options: options)
      if dryRun {
        let tree = try! SyntaxParser.parse(absoluteFile)
        try report(tester.computeStartStateAndActions(from: tree).actions, as: format)
      } else {
        try tester.run()
      }
    } catch let error as SourceKitError {
      let message = StressTesterMessage.detected(error)
      try report(message, as: format)
      return false
    }
    return true
  }

  private func report<T>(_ message: T, as format: OutputFormat) throws where T: Codable & CustomStringConvertible {
    switch format {
    case .humanReadable:
      stdoutStream <<< String(describing: message) <<< "\n"
    case .json:
      let data = try JSONEncoder().encode(message)
      stdoutStream.write(data)
      stdoutStream.write("\n".data(using: .ascii)!)
    }
    stdoutStream.flush()
  }
}

enum OutputFormat: String {
  case humanReadable
  case json
}

extension RequestSet: ArgumentKind {
  public static var completion: ShellCompletion {
    return .none
  }

  public init(argument: String) throws {
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
      throw ArgumentConversionError.unknown(value: argument)
    }
  }
}

extension OutputFormat: ArgumentKind {
  static var completion: ShellCompletion {
    return .none
  }

  init(argument: String) throws {
    guard let format = OutputFormat(rawValue: argument) else {
      throw ArgumentConversionError.unknown(value: argument)
    }
    self = format
  }
}

extension Page: ArgumentKind {
  public static var completion: ShellCompletion = .none

  public init(argument: String) throws {
    let parts = argument.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
    if parts.count == 2 {
      if let number = Int(parts[0]), let count = Int(parts[1]), number > 0, number <= count {
        self.init(number, of: count)
        return
      }
    }
    throw ArgumentConversionError.unknown(value: argument)
  }
}

extension RewriteMode: ArgumentKind {
  public static var completion: ShellCompletion = .none

  public init(argument: String) throws {
    guard let mode = RewriteMode(rawValue: argument) else {
      throw ArgumentConversionError.unknown(value: argument)
    }
    self = mode
  }
}
