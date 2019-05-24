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

import SwiftLang
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

  func codeComplete(offset: Int) throws -> (RequestInfo, SourceKitdResponse) {
    let request = SourceKitdRequest(uid: .request_CodeComplete)

    request.addParameter(.key_SourceFile, value: file)
    request.addParameter(.key_Offset, value: offset)

    let compilerArgs = request.addArrayParameter(.key_CompilerArgs)
    for arg in args { compilerArgs.add(arg) }

    let info = RequestInfo.codeComplete(document: documentInfo, offset: offset, args: args)
    let response = try sendWithTimeout(request, info: info)
    try throwIfInvalid(response, request: info)

    return (info, response)
  }

  func typeContextInfo(offset: Int) throws -> (RequestInfo, SourceKitdResponse) {
    let request = SourceKitdRequest(uid: .request_TypeContextInfo)

    request.addParameter(.key_SourceFile, value: file)
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
      throw SourceKitError.failed(.errorResponse, request: request, response: response.description.chomp())
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
        try SyntaxVerifier.verify(tree)
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
struct SourceState {
  let mode: RewriteMode
  var source: String
  var wasModified: Bool

  init(rewriteMode: RewriteMode, content source: String, wasModified: Bool = false) {
    self.mode = rewriteMode
    self.source = source
    self.wasModified = wasModified
  }

  /// - returns: true if source state changed
  @discardableResult
  mutating func replace(offset: Int, length: Int, with text: String) -> Bool {
    let bytes = source.utf8
    let prefix = bytes.prefix(upTo: bytes.index(bytes.startIndex, offsetBy: offset))
    let suffix = bytes.suffix(from: bytes.index(bytes.startIndex, offsetBy: offset + length))
    source = String(prefix)! + text + String(suffix)!
    let changed = length > 0 || !text.isEmpty
    wasModified = wasModified || changed
    return changed
  }
}
