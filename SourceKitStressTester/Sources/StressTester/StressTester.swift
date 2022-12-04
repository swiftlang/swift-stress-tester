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

public class StressTester {
  let options: StressTesterOptions
  let connection: SourceKitdService
  /// For different request kinds, the number of instructions that were executed to server the request.
  /// For all SourceKit requests, this contains the number of instructions executed by `sourcekitd`.
  /// For `ReplaceText`, this includes the number of instructions the `SwiftParser` running in this process took to parse the file.
  var requestDurations: [RequestKind: [Timing]] = [:]

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

  public func run(swiftc: String, compilerArgs: CompilerArgs, extraCodeCompleteOptions: [String:String] = [:]) -> [Error] {
    let document = SourceKitDocument(swiftc: swiftc,
                                     args: compilerArgs,
                                     tempDir: options.tempDir,
                                     connection: connection,
                                     extraCodeCompleteOptions: extraCodeCompleteOptions,
                                     containsErrors: true)
    defer {
      // Save the request durations in a 'defer' block to make sure we're also
      // saving them if a request fails
      if let timingsFile = options.requestDurationsOutputFile {
        // We are only keeping track of code completion durations for now.
        // This could easily be expanded to other request types.
        for (requestKind, timings) in requestDurations {
          try? RequestDurationManager(jsonFile: timingsFile).add(timings: timings, for: compilerArgs.forFile.path, requestKind: requestKind)
        }
      }
    }

    // compute the actions for the entire tree
    let tree: SourceFileSyntax
    do {
      tree = try document.open(rewriteMode: options.rewriteMode).0
    } catch {
      return [error]
    }
    let (actions, priorActions) = computeActions(from: tree)


    if let dryRunAction = options.dryRun {
      do {
        try dryRunAction(actions)
      } catch {
        return [error]
      }
      return []
    }

    if !priorActions.isEmpty {
      do {
        // Update initial state
        _ = try document.update() { sourceState in
          for case .replaceText(let offset, let length, let text) in priorActions {
            sourceState.replace(offset: offset, length: length, with: text)
          }
        }
      } catch {
        return [error]
      }
    }

    var errors: [Error] = []

    // IMPORTANT: We must not execute multiple requests at once because we are
    // counting the number of instructions executed by each request using the
    // statistics request. If we executed two requests at once, we couldn't
    // assign the executed instructions to a specific request.
    for action in actions {
      if options.printActions {
        print(action)
      }
      do {
        switch action {
        case .cursorInfo(let offset):
          try report(document.cursorInfo(offset: offset))
        case .codeComplete(let offset, let expectedResult):
          try report(document.codeComplete(offset: offset, expectedResult: expectedResult))
        case .rangeInfo(let offset, let length):
          try report(document.rangeInfo(offset: offset, length: length))
        case .replaceText(let offset, let length, let text):
          try report(document.replaceText(offset: offset, length: length, text: text))
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
      } catch {
        if case SourceKitError.softTimeout(request: let request, duration: _, instructions: let .some(instructions)) = error {
          reportPerformanceMeasurement(request: request, instructions: instructions, reusingASTContext: nil)
        }
        errors.append(error)
      }
    }

    do {
      try document.close()
    } catch {
      errors.append(error)
    }
    return errors
  }

  private func computeActions(from tree: SourceFileSyntax) -> (page: [Action], priorActions: [Action]) {
    let limit = options.astBuildLimit ?? Int.max
    var astRebuilds = 0
    var locationsInvalidated = false

    var actions = generator
      .generate(for: tree)
      .filter { action in
        if let offsetFilter = options.offsetFilter, offsetFilter != action.offset {
          if case .replaceText = action {
            // Don't filter replaceText actions.
            // They are necessary to reproduce the source state we want to test.
          } else {
            return false
          }
        }
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
    
    // There are certain situations where we would issue the same request twice
    // e.g. once for the end of a token and then for the start of the next 
    // token. That's a waste of time. Filter them out.

    // A set of actions that have already been scheduled for the current soure 
    // file contents. Whenever an edit action is encountered, this gets reset.
    var existingActions: Set<Action> = []
    
    actions = actions.filter({ action in
      if case .replaceText = action {
        existingActions = []
        return true
      }
      return existingActions.insert(action).inserted
    })
    let pages = actions.divide(into: options.page.count)

    return (
      page: Array(pages[options.page.index]),
      priorActions: Array(pages[..<options.page.index].joined())
    )
  }

  private func reportPerformanceMeasurement(request: RequestInfo, instructions: Int, reusingASTContext: Bool?) {
    switch request {
    case .codeCompleteOpen(document: let document, offset: let offset, args: _):
      let timing = Timing(modification: document.modificationSummaryCode, offset: offset, instructions: instructions, reusingASTContext: reusingASTContext)
      self.requestDurations[.codeComplete, default: []].append(timing)
    case .editorReplaceText(document: let document, offset: let offset, length: _, text: _):
      if document.modification == nil {
        // FIXME: We use the modificationSummaryCode *before* the modification as the timing's description.
        // Since both 'concurrent' and 'insideOut' start by modifying 'unmodified', this results in duplicate keys.
        // Just ignore this first replaceText for now. We've got plenty of test cases without it anyway.
        break
      }
      let timing = Timing(modification: document.modificationSummaryCode, offset: offset, instructions: instructions, reusingASTContext: reusingASTContext)
      self.requestDurations[.replaceText, default: []].append(timing)
    default:
      break
    }
  }

  private func report(_ result: (request: RequestInfo, response: SourceKitdResponse, instructions: Int, reusingASTContext: Bool)) throws {
    reportPerformanceMeasurement(request: result.request, instructions: result.instructions, reusingASTContext: result.reusingASTContext)
    try report((result.request, result.response))
  }

  private func report(_ result: (RequestInfo, SourceKitdResponse)) throws {
    guard let handler = options.responseHandler else { return }

    let (request, response) = result
    switch request {
    case .codeCompleteOpen: fallthrough
    case .conformingMethodList: fallthrough
    case .typeContextInfo:
      let results = getCompletionResults(from: response.value.getArray(.key_Results))
      try handler(SourceKitResponseData(results, for: request))
    default:
      try handler(SourceKitResponseData([response.value.description], for: request))
    }
  }

  private func report(_ result: (request: RequestInfo, tree: SourceFileSyntax, response: SourceKitdResponse, instructions: Int)) throws {
    reportPerformanceMeasurement(request: result.request, instructions: result.instructions, reusingASTContext: nil)
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
  public var requests: Set<RequestKind>
  public var rewriteMode: RewriteMode
  public var conformingMethodsTypeList: [String]
  public var page: Page
  public var offsetFilter: Int?
  public var tempDir: URL
  public var astBuildLimit: Int?
  public var printActions: Bool
  public var requestDurationsOutputFile: URL?
  public var responseHandler: ((SourceKitResponseData) throws -> Void)?
  public var dryRun: (([Action]) throws -> Void)?

  public init(requests: Set<RequestKind>, rewriteMode: RewriteMode,
              conformingMethodsTypeList: [String], page: Page, offsetFilter: Int?,
              tempDir: URL, astBuildLimit: Int? = nil,
              printActions: Bool = false,
              requestDurationsOutputFile: URL? = nil,
              responseHandler: ((SourceKitResponseData) throws -> Void)? = nil,
              dryRun: (([Action]) throws -> Void)? = nil) {
    self.requests = requests
    self.rewriteMode = rewriteMode
    self.conformingMethodsTypeList = conformingMethodsTypeList
    self.page = page
    self.offsetFilter = offsetFilter
    self.tempDir = tempDir
    self.astBuildLimit = astBuildLimit
    self.printActions = printActions
    self.requestDurationsOutputFile = requestDurationsOutputFile
    self.responseHandler = responseHandler
    self.dryRun = dryRun
  }
}
