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
import GameplayKit
import SwiftSourceKit
import SwiftSyntax
import Common

public struct StressTester {
  let options: StressTesterOptions
  let connection: SourceKitdService
  let seed: UInt64?

  public init(options: StressTesterOptions) {
    self.options = options
    self.connection = SourceKitdService()

    if #available(macOS 10.11, *) {
      if let optSeed = options.requestLimitSeed {
        self.seed = optSeed
      } else {
        self.seed = SeededRNG().seed
      }
    } else {
      self.seed = nil
    }
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

  public func run(swiftc: String, compilerArgs: CompilerArgs) throws {
    var document = SourceKitDocument(swiftc: swiftc,
                                     args: compilerArgs,
                                     tempDir: options.tempDir,
                                     connection: connection,
                                     containsErrors: true)

    // compute the actions for the entire tree
    let (tree, _) = try document.open(rewriteMode: options.rewriteMode)
    let (actions, priorActions) = computeActions(from: tree)

    if let dryRunAction = options.dryRun {
      try dryRunAction(actions)
      return
    }

    if !priorActions.isEmpty {
      // Update initial state
      _ = try document.update() { sourceState in
        for case .replaceText(let offset, let length, let text) in priorActions {
          sourceState.replace(offset: offset, length: length, with: text)
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
        try document.replaceText(offset: offset, length: length, text: text)
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

    try document.close()
  }

  private func computeActions(from tree: SourceFileSyntax) -> (page: [Action], priorActions: [Action]) {
    let limit = options.requestLimit ?? Int.max

    let actions = generator.generate(for: tree)
    let filtered = actions.filter { action in
      if case .replaceText = action {
        return true
      }
      if let requestKind = action.matchingRequestKind() {
        return options.requests.contains(requestKind)
      }
      return false
    }

    let pages = randomDistribution(filtered, limit: limit, using: seed,
                                   alwaysInclude: { action in
                                    if case .replaceText = action {
                                      return true
                                    }
                                    return false
                                   })
      .divide(into: options.page.count)

    return (
      page: Array(pages[options.page.index]),
      priorActions: Array(pages[..<options.page.index].joined())
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
      try handler(SourceKitResponseData([response.value.description],
                                        for: request))
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

private extension Action {
  func matchingRequestKind() -> RequestKind? {
    switch self {
    case .cursorInfo:
      return .cursorInfo
    case .rangeInfo:
      return.rangeInfo
    case .format:
      return .format
    case .codeComplete:
      return .codeComplete
    case .typeContextInfo:
      return .typeContextInfo
    case .conformingMethodList:
      return .conformingMethodList
    case .collectExpressionType:
      return .collectExpressionType
    case .testModule:
      return .testModule
    case .replaceText:
      return nil
    }
  }
}

private extension SourceKitdUID {
  static let kind_CompletionContextOtherModule = SourceKitdUID(string: "source.codecompletion.context.othermodule")
  static let kind_CompletionContextThisModule = SourceKitdUID(string: "source.codecompletion.context.thismodule")
}

public struct StressTesterOptions {
  public var requests: Set<RequestKind>
  public var rewriteMode: RewriteMode
  public var conformingMethodsTypeList: [String]
  public var page: Page
  public var tempDir: URL
  public var requestLimit: Int?
  public var requestLimitSeed: UInt64?
  public var responseHandler: ((SourceKitResponseData) throws -> Void)?
  public var dryRun: (([Action]) throws -> Void)?

  public init(requests: Set<RequestKind>, rewriteMode: RewriteMode,
              conformingMethodsTypeList: [String], page: Page,
              tempDir: URL, requestLimit: Int? = nil,
              requestLimitSeed: UInt64? = nil,
              responseHandler: ((SourceKitResponseData) throws -> Void)? = nil,
              dryRun: (([Action]) throws -> Void)? = nil) {
    self.requests = requests
    self.rewriteMode = rewriteMode
    self.conformingMethodsTypeList = conformingMethodsTypeList
    self.page = page
    self.tempDir = tempDir
    self.requestLimit = requestLimit
    self.requestLimitSeed = requestLimitSeed
    self.responseHandler = responseHandler
    self.dryRun = dryRun
  }
}

@available(macOS 10.11, *)
private struct SeededRNG : RandomNumberGenerator {
  private let random: GKMersenneTwisterRandomSource

  public var seed: UInt64 { return random.seed }

  init(seed: UInt64? = nil) {
    if let seed = seed {
      self.random = GKMersenneTwisterRandomSource(seed: seed)
    } else {
      self.random = GKMersenneTwisterRandomSource()
    }
  }

  mutating func next() -> UInt64 {
    let part1 = UInt64(bitPattern: Int64(random.nextInt()))
    let part2 = UInt64(bitPattern: Int64(random.nextInt()))
    return part1 ^ (part2 << 32)
  }
}

/// Return a random distribution of elements up to limit. Include all
/// elements matching alwaysInclude, which aren't included in the limit
/// calculation.
private func randomDistribution<T>(_ elements: [T], limit: Int,
                                   using seed: UInt64?,
                                   alwaysInclude: ((T) -> Bool)? = nil) -> [T] {
  if limit >= elements.count {
    return elements
  }

  var indices: [Int] = elements.enumerated().compactMap({ (i, e) in
    if let alwaysInclude = alwaysInclude, alwaysInclude(e) {
      return nil
    }
    return i
  })

  if limit >= indices.count {
    return elements
  }

  var rng: RandomNumberGenerator
  if #available(macOS 10.11, *), let seed = seed {
    rng = SeededRNG(seed: seed)
  } else {
    rng = SystemRandomNumberGenerator()
  }

  for i in stride(from: indices.count - 1, to: indices.count - limit, by: -1) {
    indices.swapAt(i, Int(rng.next(upperBound: UInt(i) + 1)))
  }

  let selection = Set(indices.suffix(limit))
  return elements.enumerated().compactMap({ (i, e) in
    if let alwaysInclude = alwaysInclude, alwaysInclude(e) {
      return e
    }
    if selection.contains(i) {
      return e
    }
    return nil
  })
}
