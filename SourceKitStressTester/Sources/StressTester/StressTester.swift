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
import SwiftLang
import SwiftSyntax
import Common

struct StressTester {
  let file: URL
  let source: String
  let compilerArgs: [String]
  let options: StressTesterOptions
  let connection: SourceKitdService

  init(for file: URL, compilerArgs: [String], options: StressTesterOptions) {
    self.file = file
    self.source = try! String(contentsOf: file, encoding: .utf8)
    self.compilerArgs = compilerArgs
    self.options = options
    self.connection = SourceKitdService()
  }

  var generator: ActionGenerator {
    switch options.rewriteMode {
    case .none:
      return RequestActionGenerator()
    case .basic:
      return RewriteActionGenerator()
    case .insideOut:
      return InsideOutRewriteActionGenerator()
    case .concurrent:
      return ConcurrentRewriteActionGenerator()
    }
  }

  func computeStartStateAndActions(from tree: SourceFileSyntax) -> (state: SourceState, actions: [Action]) {
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
        }
      }
      .divide(into: options.page.count)

    let page = Array(pages[options.page.index])
    guard !options.page.isFirst else {
      return (SourceState(rewriteMode: options.rewriteMode, content: source), page)
    }

    // Compute the initial state of the source file for this page
    var state = SourceState(rewriteMode: options.rewriteMode, content: source)
    pages[0..<options.page.index].joined().forEach {
      if case .replaceText(let offset, let length, let text) = $0 {
        state.replace(offset: offset, length: length, with: text)
      }
    }
    return (state, page)
  }

  func run() throws {
    if options.rewriteMode == .none {
      try readOnlyRun()
    } else {
      try rewriteRun()
    }
  }

  private func readOnlyRun() throws {
    var document = SourceKitDocument(file.path, args: compilerArgs, connection: connection)

    let (tree, _) = try document.open()
    let (state, actions) = self.computeStartStateAndActions(from: tree)

    // The action reording below requires no actions that modify the source
    // buffer are present
    precondition(!state.wasModified)
    precondition(actions.allSatisfy {
      switch $0 {
      case .replaceText:
        return false
      default:
        return true
      }
    })
    // It also doesn't make sense to have more than 1 CollectExpressionType action when
    // the source buffer is never modified
    precondition(actions.filter {
      switch $0 {
      case .collectExpressionType:
        return true
      default:
        return false
      }
    }.count <= 1)

    // Run all requests that can reuse a single AST together for improved
    // runtime
    let cursorInfos = actions.compactMap { action -> Int? in
      guard case .cursorInfo(let offset) = action else { return nil }
      return offset
    }
    let rangeInfos = actions.compactMap { action -> (offset: Int, length: Int)? in
      guard case .rangeInfo(let range) = action else { return nil }
      return range
    }
    let codeCompletions = actions.compactMap { action -> Int? in
      guard case .codeComplete(let offset) = action else { return nil }
      return offset
    }
    let typeContextInfos = actions.compactMap { action -> Int? in
      guard case .typeContextInfo(let offset) = action else { return nil }
      return offset
    }
    let conformingMethodLists = actions.compactMap { action -> Int? in
      guard case .conformingMethodList(let offset) = action else { return nil }
      return offset
    }
    let collectExpressionType = actions.contains { action -> Bool in
      guard case .collectExpressionType = action else { return false }
      return true
    }

    if collectExpressionType {
      try report(document.collectExpressionType())
    }
    for offset in cursorInfos {
      try report(document.cursorInfo(offset: offset))
    }
    for range in rangeInfos {
      try report(document.rangeInfo(offset: range.offset, length: range.length))
    }
    for offset in codeCompletions {
      try report(document.codeComplete(offset: offset))
    }
    for offset in typeContextInfos {
      try report(document.typeContextInfo(offset: offset))
    }
    for offset in conformingMethodLists {
      try report(document.conformingMethodList(offset: offset, typeList: options.conformingMethodsTypeList))
    }

    _ = try document.close()
  }

  private func report(_ result: (RequestInfo, SourceKitdResponse)) throws {
    guard let handler = options.responseHandler else { return }

    let (request, response) = result
    switch request {
    case .codeComplete: fallthrough
    case .conformingMethodList: fallthrough
    case .typeContextInfo:
      var results = [String]()
      response.value.getArray(.key_Results).enumerate { _, result -> Bool in
        results.append(result.description)
        return true
      }
      try handler(SourceKitResponseData(results, for: request))
    default:
      try handler(SourceKitResponseData([response.value.description], for: request))
    }
  }

  private func rewriteRun() throws {
    var document = SourceKitDocument(file.path, args: compilerArgs, connection: connection, containsErrors: true)

    // compute the actions for the entire tree
    let (tree, _) = try document.open()
    let (state, actions) = computeStartStateAndActions(from: tree)

    // reopen the document in the starting state
    _ = try document.close()
    _ = try document.open(state: state)

    for action in actions {
      switch action {
      case .cursorInfo(let offset):
        try report(document.cursorInfo(offset: offset))
      case .codeComplete(let offset):
        try report(document.codeComplete(offset: offset))
      case .rangeInfo(let offset, let length):
        try report(document.rangeInfo(offset: offset, length: length))
      case .replaceText(let offset, let length, let text):
        _ = try document.replaceText(offset: offset, length: length, text: text)
      case .typeContextInfo(let offset):
        try report(document.typeContextInfo(offset: offset))
      case .conformingMethodList(let offset):
        try report(document.conformingMethodList(offset: offset, typeList: options.conformingMethodsTypeList))
      case .collectExpressionType:
        try report(document.collectExpressionType())
      }
    }

    _ = try document.close()
  }
}

struct StressTesterOptions {
  var astBuildLimit: Int? = nil
  var requests: RequestSet = .all
  var rewriteMode: RewriteMode = .none
  var conformingMethodsTypeList = ["s:SQ", "s:SH"] // Equatable and Hashable
  var responseHandler: ((SourceKitResponseData) throws -> Void)? = nil
  var page = Page(1, of: 1)
}

public struct RequestSet: OptionSet {
  public let rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  public var valueNames: [String] {
    var requests = [String]()
    if self.contains(.codeComplete) {
      requests.append("CodeComplete")
    }
    if self.contains(.cursorInfo) {
      requests.append("CursorInfo")
    }
    if self.contains(.rangeInfo) {
      requests.append("RangeInfo")
    }
    if self.contains(.typeContextInfo) {
      requests.append("TypeContextInfo")
    }
    if self.contains(.conformingMethodList) {
      requests.append("ConformingMethodList")
    }
    if self.contains(.collectExpressionType) {
      requests.append("CollectExpressionType")
    }
    return requests
  }

  public static let cursorInfo = RequestSet(rawValue: 1 << 0)
  public static let rangeInfo = RequestSet(rawValue: 1 << 1)
  public static let codeComplete = RequestSet(rawValue: 1 << 2)
  public static let typeContextInfo = RequestSet(rawValue: 1 << 3)
  public static let conformingMethodList = RequestSet(rawValue: 1 << 4)
  public static let collectExpressionType = RequestSet(rawValue: 1 << 5)

  public static let all: RequestSet = [.cursorInfo, .rangeInfo, .codeComplete, .typeContextInfo, .conformingMethodList, .collectExpressionType]
}
