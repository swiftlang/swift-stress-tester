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

import SwiftSourceKit
import SwiftSyntax
import Common
import Foundation

struct SourceKitDocument {
  let file: String
  let args: [String]
  let containsErrors: Bool
  let connection: SourceKitdService

  private let diagEngine = DiagnosticEngine()
  private var tree: SourceFileSyntax? = nil
  private var converter: SourceLocationConverter? = nil
  private var sourceState: SourceState? = nil

  private var documentInfo: DocumentInfo {
    var modification: DocumentModification? = nil
    if let state = sourceState, state.wasModified {
      modification = DocumentModification(mode: state.mode, content: state.source)
    }
    return DocumentInfo(path: file, modification: modification)
  }

  // An empty diagnostic consumer to practice the diagnostic APIs associated
  // with SwiftSyntax parser.
  class EmptyDiagConsumer: DiagnosticConsumer {
    func handle(_ diagnostic: Diagnostic) {}
    func finalize() {}
    let needsLineColumn: Bool = true
  }

  init(_ file: String, args: [String], connection: SourceKitdService, containsErrors: Bool = false) {
    self.file = file
    self.args = args
    self.containsErrors = containsErrors
    self.connection = connection
    self.diagEngine.addConsumer(EmptyDiagConsumer())
  }

  mutating func open(state: SourceState? = nil) throws -> (SourceFileSyntax, SourceKitdResponse) {
    let request = SourceKitdRequest(uid: .request_EditorOpen)
    if let state = state {
      sourceState = state
      request.addParameter(.key_SourceText, value: state.source)
    } else {
      request.addParameter(.key_SourceFile, value: file)
    }
    request.addParameter(.key_Name, value: file)
    request.addParameter(.key_EnableSyntaxMap, value: 0)
    request.addParameter(.key_EnableStructure, value: 0)
    request.addParameter(.key_SyntacticOnly, value: 1)

    let compilerArgs = request.addArrayParameter(.key_CompilerArgs)
    for arg in args { compilerArgs.add(arg) }

    let info = RequestInfo.editorOpen(document: documentInfo)
    let response = try sendWithTimeout(request, info: info)
    try throwIfInvalid(response, request: info)

    try updateSyntaxTree(request: info)

    return (tree!, response)
  }

  mutating func close() throws -> SourceKitdResponse {
    sourceState = nil

    let request = SourceKitdRequest(uid: .request_EditorClose)
    request.addParameter(.key_SourceFile, value: file)
    request.addParameter(.key_Name, value: file)

    let info = RequestInfo.editorClose(document: documentInfo)
    let response = try sendWithTimeout(request, info: info)
    try throwIfInvalid(response, request: info)
    return response
  }

  func rangeInfo(offset: Int, length: Int) throws -> (RequestInfo, SourceKitdResponse) {
    let request = SourceKitdRequest(uid: .request_RangeInfo)

    request.addParameter(.key_SourceFile, value: file)
    request.addParameter(.key_Offset, value: offset)
    request.addParameter(.key_Length, value: length)
    request.addParameter(.key_RetrieveRefactorActions, value: 1)

    let compilerArgs = request.addArrayParameter(.key_CompilerArgs)
    for arg in args { compilerArgs.add(arg) }

    let info = RequestInfo.rangeInfo(document: documentInfo, offset: offset, length: length, args: args)
    let response = try sendWithTimeout(request, info: info)
    try throwIfInvalid(response, request: info)

    if let actions = response.value.getOptional(.key_RefactorActions)?.getArray() {
      for i in 0 ..< actions.count {
        let action = actions.getDictionary(i)
        guard action.getOptional(.key_ActionUnavailableReason) == nil else { continue }
        let actionName = action.getString(.key_ActionName)
        let kind = action.getUID(.key_ActionUID)
        _ = try semanticRefactoring(actionKind: kind, actionName: actionName,
                                    offset: offset)
      }
    }

    return (info, response)
  }

  func cursorInfo(offset: Int) throws -> (RequestInfo, SourceKitdResponse) {
    let request = SourceKitdRequest(uid: .request_CursorInfo)

    request.addParameter(.key_SourceFile, value: file)
    request.addParameter(.key_Offset, value: offset)
    request.addParameter(.key_RetrieveRefactorActions, value: 1)

    let compilerArgs = request.addArrayParameter(.key_CompilerArgs)
    for arg in args { compilerArgs.add(arg) }

    let info = RequestInfo.cursorInfo(document: documentInfo, offset: offset, args: args)
    let response = try sendWithTimeout(request, info: info)
    try throwIfInvalid(response, request: info)

    if !containsErrors {
      if let typeName = response.value.getOptional(.key_TypeName)?.getString(), typeName.contains("<<error type>>") {
        throw SourceKitError.failed(.errorTypeInResponse, request: info, response: response.value.description)
      }
    }

    let symbolName = response.value.getOptional(.key_Name)?.getString()
    if let actions = response.value.getOptional(.key_RefactorActions)?.getArray() {
      for i in 0 ..< actions.count {
        let action = actions.getDictionary(i)
        guard action.getOptional(.key_ActionUnavailableReason) == nil else { continue }
        let actionName = action.getString(.key_ActionName)
        guard actionName != "Global Rename" else { continue }
        let kind = action.getUID(.key_ActionUID)
        _ = try semanticRefactoring(actionKind: kind, actionName: actionName,
                                    offset: offset, newName: symbolName)
      }
    }

    return (info, response)
  }

  func semanticRefactoring(actionKind: SourceKitdUID, actionName: String,
                           offset: Int, newName: String? = nil) throws -> (RequestInfo, SourceKitdResponse) {
    let request = SourceKitdRequest(uid: .request_SemanticRefactoring)
    guard let converter = self.converter else { fatalError("didn't call open?") }

    request.addParameter(.key_ActionUID, value: actionKind)
    request.addParameter(.key_SourceFile, value: file)
    let location = converter.location(for: AbsolutePosition(utf8Offset: offset))
    request.addParameter(.key_Line, value: location.line!)
    request.addParameter(.key_Column, value: location.column!)
    if let newName = newName, actionName == "Local Rename" {
      request.addParameter(.key_Name, value: newName)
    }
    let compilerArgs = request.addArrayParameter(.key_CompilerArgs)
    for arg in args { compilerArgs.add(arg) }

    let info = RequestInfo.semanticRefactoring(document: documentInfo, offset: offset, kind: actionName, args: args)
    let response = try sendWithTimeout(request, info: info)
    try throwIfInvalid(response, request: info)

    return (info, response)
  }

  func codeComplete(offset: Int, expectedResult: ExpectedResult?) throws -> (RequestInfo, SourceKitdResponse) {
    let request = SourceKitdRequest(uid: .request_CodeComplete)

    request.addParameter(.key_SourceFile, value: file)
    if let sourceState = sourceState {
      request.addParameter(.key_SourceText, value: sourceState.source)
    }
    request.addParameter(.key_Offset, value: offset)

    let compilerArgs = request.addArrayParameter(.key_CompilerArgs)
    for arg in args { compilerArgs.add(arg) }

    let info = RequestInfo.codeComplete(document: documentInfo, offset: offset, args: args)
    let response = try sendWithTimeout(request, info: info)
    try throwIfInvalid(response, request: info)

    if let expectedResult = expectedResult {
      try checkExpectedCompletionResult(expectedResult, in: response, info: info)
    }

    return (info, response)
  }

  func typeContextInfo(offset: Int) throws -> (RequestInfo, SourceKitdResponse) {
    let request = SourceKitdRequest(uid: .request_TypeContextInfo)

    request.addParameter(.key_SourceFile, value: file)
    if let sourceState = sourceState {
      request.addParameter(.key_SourceText, value: sourceState.source)
    }
    request.addParameter(.key_Offset, value: offset)

    let compilerArgs = request.addArrayParameter(.key_CompilerArgs)
    for arg in args { compilerArgs.add(arg) }

    let info = RequestInfo.typeContextInfo(document: documentInfo, offset: offset, args: args)
    let response = try sendWithTimeout(request, info: info)
    try throwIfInvalid(response, request: info)

    return (info, response)
  }

  func conformingMethodList(offset: Int, typeList: [String]) throws -> (RequestInfo, SourceKitdResponse) {
    let request = SourceKitdRequest(uid: .request_ConformingMethodList)

    request.addParameter(.key_SourceFile, value: file)
    if let sourceState = sourceState {
      request.addParameter(.key_SourceText, value: sourceState.source)
    }
    request.addParameter(.key_Offset, value: offset)

    let expressionTypeList = request.addArrayParameter(.key_ExpressionTypeList)
    for type in typeList { expressionTypeList.add(type) }

    let compilerArgs = request.addArrayParameter(.key_CompilerArgs)
    for arg in args { compilerArgs.add(arg) }

    let info = RequestInfo.conformingMethodList(document: documentInfo, offset: offset, typeList: typeList, args: args)
    let response = try sendWithTimeout(request, info: info)
    try throwIfInvalid(response, request: info)

    return (info, response)
  }

  func collectExpressionType() throws -> (RequestInfo, SourceKitdResponse) {
    let request = SourceKitdRequest(uid: .request_CollectExpressionType)

    request.addParameter(.key_SourceFile, value: file)

    let compilerArgs = request.addArrayParameter(.key_CompilerArgs)
    for arg in args { compilerArgs.add(arg) }

    let info = RequestInfo.collectExpressionType(document: documentInfo, args: args)
    let response = try sendWithTimeout(request, info: info)
    try throwIfInvalid(response, request: info)

    return (info, response)
  }

  mutating func replaceText(offset: Int, length: Int, text: String) throws -> (SourceFileSyntax, SourceKitdResponse) {
    let request = SourceKitdRequest(uid: .request_EditorReplaceText)
    request.addParameter(.key_Name, value: file)
    request.addParameter(.key_Offset, value: offset)
    request.addParameter(.key_Length, value: length)
    request.addParameter(.key_SourceText, value: text)

    request.addParameter(.key_EnableSyntaxMap, value: 0)
    request.addParameter(.key_EnableStructure, value: 0)
    request.addParameter(.key_SyntacticOnly, value: 1)

    let info = RequestInfo.editorReplaceText(document: documentInfo, offset: offset, length: length, text: text)
    let response = try sendWithTimeout(request, info: info)
    try throwIfInvalid(response, request: info)

    // update expected source content and syntax tree
    sourceState?.replace(offset: offset, length: length, with: text)
    try updateSyntaxTree(request: info)

    return (tree!, response)
  }

  private func checkExpectedCompletionResult(_ expected: ExpectedResult, in response: SourceKitdResponse, info: RequestInfo) throws {
    let matcher = CompletionMatcher(for: expected)
    var found = false
    response.value.getArray(.key_Results).enumerate { (_, item) -> Bool in
      let result = item.getDictionary()
      found = matcher.match(result.getString(.key_Name), ignoreArgLabels: shouldIgnoreArgs(of: expected, for: result))
      return !found
    }
    if !found {
        throw SourceKitError.failed(.missingExpectedResult, request: info, response: response.description.spm_chomp())
    }
  }

  private func shouldIgnoreArgs(of expected: ExpectedResult, for result: SourceKitdResponse.Dictionary) -> Bool {
    switch result.getUID(.key_Kind) {
    case .kind_DeclStruct, .kind_DeclClass, .kind_DeclEnum, .kind_DeclTypeAlias:
      // Initializer calls look like function calls syntactically, but the
      // completion results only include the type name. Allow for that by
      // matching on the base name only.
      return expected.kind == .call
    case .kind_DeclVarGlobal, .kind_DeclVarStatic, .kind_DeclVarClass, .kind_DeclVarInstance, .kind_DeclVarParam, .kind_DeclVarLocal:
      // Any variable/property of function type can be called, and looks the
      // same as a function call as far as the expected result is concerned,
      // but it's name won't have any argument labels.
      // If the expected result is a call that only has empty argument labels
      // (if any), it *may* be in this category, so match on the base name only.
      return expected.kind == .call && expected.name.argLabels.allSatisfy{ $0.isEmpty }
    default:
      return false
    }
  }

  private func sendWithTimeout(_ request: SourceKitdRequest, info: RequestInfo) throws -> SourceKitdResponse {
    var response: SourceKitdResponse? = nil
    let completed = DispatchSemaphore(value: 0)
    connection.send(request: request) {
      response = $0
      completed.signal()
    }
    switch completed.wait(timeout: .now() + DispatchTimeInterval.seconds(300)) {
    case .success:
      return response!
    case .timedOut:
      throw SourceKitError.timedOut(request: info)
    }
  }

  private func throwIfInvalid(_ response: SourceKitdResponse, request: RequestInfo) throws {
    if response.isCompilerCrash || response.isConnectionInterruptionError {
      throw SourceKitError.crashed(request: request)
    }
    // FIXME: We don't supply a valid new name for initializer calls for local
    // rename requests. Ignore these errors for now.
    if response.isError, !response.description.contains("does not match the arity of the old name") {
      throw SourceKitError.failed(.errorResponse, request: request, response: response.description.spm_chomp())
    }
  }

  private func parseSyntax(request: RequestInfo) throws -> SourceFileSyntax {
    let reparseTransition: IncrementalParseTransition?
    switch request {
    case .editorReplaceText(_, let offset, let length, let text):
      let edits = [SourceEdit(range: ByteSourceRange(offset: offset, length: length), replacementLength: text.utf8.count)]
      reparseTransition = IncrementalParseTransition(previousTree: self.tree!, edits: edits)
    default:
      reparseTransition = nil
    }

    let tree: SourceFileSyntax
    if let state = sourceState {
      tree = try SyntaxParser.parse(source: state.source,
                                    parseTransition: reparseTransition,
                                    diagnosticEngine: diagEngine)
    } else {
      tree = try SyntaxParser.parse(URL(fileURLWithPath: file),
                                    diagnosticEngine: diagEngine)
    }
    return tree
  }

  @discardableResult
  private mutating func updateSyntaxTree(request: RequestInfo) throws -> SourceFileSyntax {
    let tree: SourceFileSyntax
    do {
      tree = try parseSyntax(request: request)
    } catch let error {
      throw SourceKitError.failed(.errorDeserializingSyntaxTree, request: request, response: error.localizedDescription)
    }
    self.tree = tree
    self.converter = SourceLocationConverter(file: "", tree: tree)

    /// When we should be able to fully parse the file, we verify the syntax tree
    if !containsErrors {
      do {
        try SyntaxVerifier.verify(Syntax(tree))
      } catch let error as SyntaxVerifierError {
        throw SourceKitError.failed(.errorDeserializingSyntaxTree, request: request, response: error.description)
      }
    }

    if let state = sourceState, state.source != tree.description {
      // FIXME: add state and tree descriptions in their own field
      let comparison = """
        --source-state------
        \(state.source)
        --tree-description--
        \(tree.description)
        --end---------------
        """
      throw SourceKitError.failed(.sourceAndSyntaxTreeMismatch, request: request, response: comparison)
    }

    return tree
  }
}

/// Tracks the current state of a source file
public struct SourceState {
  public let mode: RewriteMode
  public var source: String
  public var wasModified: Bool

  public init(rewriteMode: RewriteMode, content source: String, wasModified: Bool = false) {
    self.mode = rewriteMode
    self.source = source
    self.wasModified = wasModified
  }

  /// - returns: true if source state changed
  @discardableResult
  public mutating func replace(offset: Int, length: Int, with text: String) -> Bool {
    let bytes = source.utf8
    let prefix = bytes.prefix(upTo: bytes.index(bytes.startIndex, offsetBy: offset))
    let suffix = bytes.suffix(from: bytes.index(bytes.startIndex, offsetBy: offset + length))
    source = String(prefix)! + text + String(suffix)!
    let changed = length > 0 || !text.isEmpty
    wasModified = wasModified || changed
    return changed
  }
}

public struct CompletionMatcher {
  private let expected: ExpectedResult

  public init(for expected: ExpectedResult) {
    self.expected = expected
  }

  /// - returns: true if a match was found
  public func match(_ result: String, ignoreArgLabels: Bool) -> Bool {
    if ignoreArgLabels {
      let name = SwiftName(result)!
      return name.base == expected.name.base
    }
    // Check if the base name and/or argument labels match based on the expected
    // result kind.
    return matches(name: result)
  }

  private func matches(name: String) -> Bool {
    let resultName = SwiftName(name)!
    guard resultName.base == expected.name.base else { return false }
    switch expected.kind {
    case .call:
      return name.last == ")" && matchesCall(paramLabels: resultName.argLabels)
    case .reference:
      return expected.name.argLabels.isEmpty || expected.name.argLabels == resultName.argLabels
    case .pattern:
      // If the expected result didn't match on the associated value: it matches
      if expected.name.argLabels.isEmpty {
        return true
      }

      // Result names for enum cases work differently to functions in that
      // unlabelled items in the associated values aren't represented, e.g.:
      //   case foo              // name: foo
      //   case foo(Int, Int)    // name: foo()
      //   case foo(x: Int, Int) // name: foo(x:)
      //   case foo(Int, y: Int) // name: foo(y:)

      // If the result name doesn't have an associated value, but the expected
      // name does: it doesn't match
      if name.last != ")" && !expected.name.argLabels.isEmpty {
        return false
      }

      // If the expected result bound the entire associated value to a single
      // unlabelled variable, we're done
      if expected.name.argLabels == [""] {
        return true
      }

      // Otherwise the expected argument labels must either match the
      // corresponding result arg labels or be "" since they don't have to be
      // specified when pattern matching.
      var unmatched = resultName.argLabels[...]
      return expected.name.argLabels.allSatisfy{ label in
        if label.isEmpty { return true }
        if let labelIndex = unmatched.firstIndex(of: label) {
          unmatched = unmatched.dropFirst(labelIndex - unmatched.startIndex + 1)
          return true
        }
        return false
      }
    }
  }

  private func matchesCall(paramLabels: [String]) -> Bool {
    var remainingArgLabels = expected.name.argLabels[...]

    guard !paramLabels.isEmpty else { return remainingArgLabels.isEmpty }
    for nextParamLabel in paramLabels {
      if nextParamLabel.isEmpty {
        // No label
        if let first = remainingArgLabels.first, first.isEmpty {
          // Matched - consume the argument
          _ = remainingArgLabels.removeFirst()
        } else {
          // Assume this was defaulted and skip over it
          continue
        }
      } else {
        // Has param label
        if remainingArgLabels.count < expected.name.argLabels.count {
          // A previous param was matched, so assume it was variadic and consume
          // any leading unlabelled args so the next arg is labelled
          remainingArgLabels = remainingArgLabels.drop{ $0.isEmpty }
        }
        guard let nextArgLabel = remainingArgLabels.first else {
          // Assume any unprocessed parameters are defaulted
          return true
        }
        if nextArgLabel == nextParamLabel {
          // Matched - consume the argument
          _ = remainingArgLabels.removeFirst()
          continue
        }
        // Else assume this param was defaulted and skip it.
      }
    }
    // If at least one arglabel was matched, allow for it being variadic
    let hadMatch = remainingArgLabels.count < expected.name.argLabels.count
    return  remainingArgLabels.isEmpty || hadMatch &&
      remainingArgLabels.allSatisfy { $0.isEmpty }
  }
}
