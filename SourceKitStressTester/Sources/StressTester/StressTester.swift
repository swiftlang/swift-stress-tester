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

import Foundation
import SwiftSourceKit
import SwiftSyntax
import Common

public struct StressTester {
  let options: StressTesterOptions
  let connection: SourceKitdService

  public init(options: StressTesterOptions) {
    self.options = options
    self.connection = SourceKitdService()
  }

  var generator: ActionGenerator {
    switch options.rewriteMode {
    case .none:
      return RequestActionGenerator()
    case .typoed:
      return TypoActionGenerator()
    case .basic:
      return BasicRewriteActionGenerator()
    case .insideOut:
      return InsideOutRewriteActionGenerator()
    case .concurrent:
      return ConcurrentRewriteActionGenerator()
    }
  }

  public func run(for file: URL, swiftc: String, compilerArgs: [String]) throws {
    let compilerArgs = compilerArgs.flatMap {
      DriverFileList(at: $0)?.paths ?? [$0]
    }
    var document = SourceKitDocument(file,
                                     swiftc: swiftc,
                                     args: compilerArgs,
                                     tempDir: options.tempDir,
                                     connection: connection,
                                     containsErrors: true)

    // compute the actions for the entire tree
    let (tree, _) = try document.open(rewriteMode: options.rewriteMode)
    let (actions, replacements) = computeActions(from: tree)

    if let dryRunAction = options.dryRun {
      try dryRunAction(actions)
      return
    }

    if !replacements.isEmpty {
      // Update initial state
      _ = try document.update() { sourceState in
        for action in replacements {
          if case .replaceText(let offset, let length, let text) = action {
            sourceState.replace(offset: offset, length: length, with: text)
          }
        }
      }
    }

    for action in actions {
      switch action {
      case .cursorInfo(let offset):
        try report(document.cursorInfo(offset: offset))
      case .codeComplete(let offset, let expectedResult):
        try report(document.codeComplete(offset: offset, expectedResult: expectedResult))
      case .rangeInfo(let offset, let length):
        try report(document.rangeInfo(offset: offset, length: length))
      case .replaceText(let offset, let length, let text):
        _ = try document.replaceText(offset: offset, length: length, text: text)
      case .format(let offset):
        try report(document.format(offset: offset))
      case .typeContextInfo(let offset):
        try report(document.typeContextInfo(offset: offset))
      case .conformingMethodList(let offset):
        try report(document.conformingMethodList(offset: offset, typeList: options.conformingMethodsTypeList))
      case .collectExpressionType:
        try report(document.collectExpressionType())
      case .testModule:
        try report(document.moduleInterfaceGen())
      }
    }

    _ = try document.close()
  }

  private func computeActions(from tree: SourceFileSyntax) -> (page: [Action], replacements: [Action]) {
    let limit = options.astBuildLimit ?? Int.max
    var astRebuilds = 0
    var locationsInvalidated = false

    let pages = generator
      .generate(for: tree)
      .filter { action in
        guard !locationsInvalidated else { return false }
        switch action {
        case .cursorInfo:
          return options.requests.contains(.cursorInfo)
        case .rangeInfo:
          return options.requests.contains(.rangeInfo)
        case .format:
          return options.requests.contains(.format)
        case .codeComplete:
          guard options.requests.contains(.codeComplete), astRebuilds <= limit else { return false }
          astRebuilds += 1
          return true
        case .typeContextInfo:
          guard options.requests.contains(.typeContextInfo), astRebuilds <= limit else { return false}
          astRebuilds += 1
          return true
        case .conformingMethodList:
          guard options.requests.contains(.conformingMethodList), astRebuilds <= limit else { return false }
          astRebuilds += 1
          return true
        case .collectExpressionType:
          return options.requests.contains(.collectExpressionType)
        case .replaceText:
          guard astRebuilds <= limit else {
            locationsInvalidated = true
            return false
          }
          astRebuilds += 1
          return true
        case .testModule:
          return options.requests.contains(.testModule)
        }
      }
      .divide(into: options.page.count)

    return (
      page: Array(pages[options.page.index]),
      replacements: pages[..<options.page.index].joined()
        .filter {
          if case .replaceText = $0 {
            return true
          }
          return false
        }
    )
  }

  private func report(_ result: (RequestInfo, SourceKitdResponse)) throws {
    guard let handler = options.responseHandler else { return }

    let (request, response) = result
    switch request {
    case .codeComplete: fallthrough
    case .conformingMethodList: fallthrough
    case .typeContextInfo:
      let results = getCompletionResults(from: response.value.getArray(.key_Results))
      try handler(SourceKitResponseData(results, for: request))
    default:
      try handler(SourceKitResponseData([response.value.description], for: request))
    }
  }

  private func getCompletionResults(from results: SourceKitdResponse.Array) -> [String] {
    var global = [String]()
    var module = [String]()
    var local = [String]()
    results.enumerate { _, result -> Bool in
      let value = result.getDictionary()
      let name = value.getString(.key_Name)
      switch value.getUID(.key_Context) {
      case .kind_CompletionContextOtherModule:
        global.append(name)
      case .kind_CompletionContextThisModule:
        module.append(name)
      default:
        local.append(name)
      }
      return true
    }

    return [("global", global), ("module", module), ("local", local)].map { label, results in
      "\(label): \(results.isEmpty ? "<empty>" : results.sorted().joined(separator: ", "))"
    }
  }
}

private extension SourceKitdUID {
  static let kind_CompletionContextOtherModule = SourceKitdUID(string: "source.codecompletion.context.othermodule")
  static let kind_CompletionContextThisModule = SourceKitdUID(string: "source.codecompletion.context.thismodule")
}

public struct StressTesterOptions {
  public var requests: RequestSet
  public var rewriteMode: RewriteMode
  public var conformingMethodsTypeList: [String]
  public var page: Page
  public var tempDir: URL
  public var astBuildLimit: Int?
  public var responseHandler: ((SourceKitResponseData) throws -> Void)?
  public var dryRun: (([Action]) throws -> Void)?

  public init(requests: RequestSet, rewriteMode: RewriteMode,
              conformingMethodsTypeList: [String], page: Page,
              tempDir: URL, astBuildLimit: Int? = nil,
              responseHandler: ((SourceKitResponseData) throws -> Void)? = nil,
              dryRun: (([Action]) throws -> Void)? = nil) {
    self.requests = requests
    self.rewriteMode = rewriteMode
    self.conformingMethodsTypeList = conformingMethodsTypeList
    self.page = page
    self.tempDir = tempDir
    self.astBuildLimit = astBuildLimit
    self.responseHandler = responseHandler
    self.dryRun = dryRun
  }
}

public struct RequestSet: OptionSet {
  public let rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  public var valueNames: [String] {
    var requests = [String]()
    if contains(.codeComplete) {
      requests.append("CodeComplete")
    }
    if contains(.cursorInfo) {
      requests.append("CursorInfo")
    }
    if contains(.rangeInfo) {
      requests.append("RangeInfo")
    }
    if contains(.typeContextInfo) {
      requests.append("TypeContextInfo")
    }
    if contains(.conformingMethodList) {
      requests.append("ConformingMethodList")
    }
    if contains(.collectExpressionType) {
      requests.append("CollectExpressionType")
    }
    if contains(.testModule) {
      requests.append("TestModule")
    }
    return requests
  }

  public static let cursorInfo = RequestSet(rawValue: 1 << 0)
  public static let rangeInfo = RequestSet(rawValue: 1 << 1)
  public static let codeComplete = RequestSet(rawValue: 1 << 2)
  public static let typeContextInfo = RequestSet(rawValue: 1 << 3)
  public static let conformingMethodList = RequestSet(rawValue: 1 << 4)
  public static let collectExpressionType = RequestSet(rawValue: 1 << 5)
  public static let format = RequestSet(rawValue: 1 << 6)
  public static let testModule = RequestSet(rawValue: 1 << 7)

  public static let ide: RequestSet = [.cursorInfo, .rangeInfo, .codeComplete,
                                      .typeContextInfo, .conformingMethodList,
                                      .collectExpressionType, .format]
  public static let all: RequestSet = ide.union(RequestSet([.testModule]))
}

extension RequestSet: CustomStringConvertible {
  public var description: String {
    if self == .ide {
      return "\"IDE\""
    } else if self == .all {
      return "\"All\""
    }
    return String(describing: valueNames)
  }
}
