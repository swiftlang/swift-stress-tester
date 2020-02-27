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
import TSCBasic

public protocol Message: Codable, CustomStringConvertible {}

public extension Message {
  func write(to stream: FileOutputByteStream) throws {
    let data: Data = try JSONEncoder().encode(self)
    // messages are separated by newlines
    stream <<< data <<< "\n"
    stream.flush()
  }

  init?(from data: Data) {
    guard let message = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
    self = message
  }
}

public enum StressTesterMessage: Message {
  case detected(SourceKitError)
  case produced(SourceKitResponseData)
}

public struct SourceKitResponseData: Codable {
  public let request: RequestInfo
  public let results: [String]

  public init(_ results: [String], for request: RequestInfo) {
    self.results = results
    self.request = request
  }
}

public enum SourceKitError: Error {
  case crashed(request: RequestInfo)
  case timedOut(request: RequestInfo)
  case failed(_ reason: SourceKitErrorReason, request: RequestInfo, response: String)

  public var request: RequestInfo {
    switch self {
    case .crashed(let request):
      return request
    case .timedOut(let request):
      return request
    case .failed(_, let request, _):
      return request
    }
  }
}

public enum SourceKitErrorReason: String, Codable {
  case errorResponse, errorTypeInResponse, errorDeserializingSyntaxTree, sourceAndSyntaxTreeMismatch, missingExpectedResult
}

public enum RequestInfo {
  case editorOpen(document: DocumentInfo)
  case editorClose(document: DocumentInfo)
  case editorReplaceText(document: DocumentInfo, offset: Int, length: Int, text: String)
  case format(document: DocumentInfo, offset: Int)
  case cursorInfo(document: DocumentInfo, offset: Int, args: [String])
  case codeComplete(document: DocumentInfo, offset: Int, args: [String])
  case rangeInfo(document: DocumentInfo, offset: Int, length: Int, args: [String])
  case semanticRefactoring(document: DocumentInfo, offset: Int, kind: String, args: [String])
  case typeContextInfo(document: DocumentInfo, offset: Int, args: [String])
  case conformingMethodList(document: DocumentInfo, offset: Int, typeList: [String], args: [String])
  case collectExpressionType(document: DocumentInfo, args: [String])
}

public struct DocumentInfo: Codable {
  public let path: String
  public let modification: DocumentModification?

  public init(path: String, modification: DocumentModification? = nil) {
    self.path = path
    self.modification = modification
  }
}

public struct DocumentModification: Codable {
  public let mode: RewriteMode
  public let content: String

  public init(mode: RewriteMode, content: String) {
    self.mode = mode
    self.content = content
  }
}

public enum RewriteMode: String, Codable, CaseIterable {
  /// Do not rewrite the file (only make non-modifying SourceKit requests)
  case none
  /// Rewrite each identifier to be mispelled
  case typoed
  /// Rewrite the file token by token, top to bottom
  case basic
  /// Rewrite all top level declarations top to bottom, concurrently
  case concurrent
  /// Rewrite the file from the most deeply nested tokens to the least
  case insideOut
}

public struct Page: Codable {
  public let number: Int
  public let count: Int
  public var isFirst: Bool {
    return number == 1
  }
  public var index: Int {
    return number - 1
  }

  public init(_ number: Int, of count: Int) {
    assert(number >= 1 && number <= count)
    self.number = number
    self.count = count
  }
}

extension StressTesterMessage: Codable {
  enum CodingKeys: String, CodingKey {
    case message, error, responseData
  }
  enum BaseMessage: String, Codable {
    case detected, produced
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(BaseMessage.self, forKey: .message) {
    case .detected:
      let error = try container.decode(SourceKitError.self, forKey: .error)
      self = .detected(error)
    case .produced:
      let responseData = try container.decode(SourceKitResponseData.self, forKey: .responseData)
      self = .produced(responseData)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .detected(let error):
      try container.encode(BaseMessage.detected, forKey: .message)
      try container.encode(error, forKey: .error)
    case .produced(let responseData):
      try container.encode(BaseMessage.produced, forKey: .message)
      try container.encode(responseData, forKey: .responseData)
    }
  }
}

extension SourceKitError: Codable {
  enum CodingKeys: String, CodingKey {
    case error, kind, request, response
  }
  enum BaseError: String, Codable {
    case crashed, failed, timedOut
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(BaseError.self, forKey: .error) {
    case .crashed:
      let request = try container.decode(RequestInfo.self, forKey: .request)
      self = .crashed(request: request)
    case .timedOut:
      let request = try container.decode(RequestInfo.self, forKey: .request)
      self = .timedOut(request: request)
    case .failed:
      let reason = try container.decode(SourceKitErrorReason.self, forKey: .kind)
      let request = try container.decode(RequestInfo.self, forKey: .request)
      let response = try container.decode(String.self, forKey: .response)
      self = .failed(reason, request: request, response: response)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .crashed(let request):
      try container.encode(BaseError.crashed, forKey: .error)
      try container.encode(request, forKey: .request)
    case .timedOut(let request):
      try container.encode(BaseError.timedOut, forKey: .error)
      try container.encode(request, forKey: .request)
    case .failed(let kind, let request, let response):
      try container.encode(BaseError.failed, forKey: .error)
      try container.encode(kind, forKey: .kind)
      try container.encode(request, forKey: .request)
      try container.encode(response, forKey: .response)
    }
  }
}

extension RequestInfo: Codable {
  enum CodingKeys: String, CodingKey {
    case request, kind, document, offset, length, text, args, typeList
  }
  enum BaseRequest: String, Codable {
    case editorOpen, editorClose, replaceText, format, cursorInfo, codeComplete,
      rangeInfo, semanticRefactoring, typeContextInfo, conformingMethodList,
      collectExpressionType
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(BaseRequest.self, forKey: .request) {
    case .editorOpen:
      let document = try container.decode(DocumentInfo.self, forKey: .document)
      self = .editorOpen(document: document)
    case .editorClose:
      let document = try container.decode(DocumentInfo.self, forKey: .document)
      self = .editorClose(document: document)
    case .cursorInfo:
      let document = try container.decode(DocumentInfo.self, forKey: .document)
      let offset = try container.decode(Int.self, forKey: .offset)
      let args = try container.decode([String].self, forKey: .args)
      self = .cursorInfo(document: document, offset: offset, args: args)
    case .codeComplete:
      let document = try container.decode(DocumentInfo.self, forKey: .document)
      let offset = try container.decode(Int.self, forKey: .offset)
      let args = try container.decode([String].self, forKey: .args)
      self = .codeComplete(document: document, offset: offset, args: args)
    case .rangeInfo:
      let document = try container.decode(DocumentInfo.self, forKey: .document)
      let offset = try container.decode(Int.self, forKey: .offset)
      let length = try container.decode(Int.self, forKey: .length)
      let args = try container.decode([String].self, forKey: .args)
      self = .rangeInfo(document: document, offset: offset, length: length, args: args)
    case .semanticRefactoring:
      let document = try container.decode(DocumentInfo.self, forKey: .document)
      let offset = try container.decode(Int.self, forKey: .offset)
      let kind = try container.decode(String.self, forKey: .kind)
      let args = try container.decode([String].self, forKey: .args)
      self = .semanticRefactoring(document: document, offset: offset, kind: kind, args: args)
    case .replaceText:
      let document = try container.decode(DocumentInfo.self, forKey: .document)
      let offset = try container.decode(Int.self, forKey: .offset)
      let length = try container.decode(Int.self, forKey: .length)
      let text = try container.decode(String.self, forKey: .text)
      self = .editorReplaceText(document: document, offset: offset, length: length, text: text)
    case .format:
      let document = try container.decode(DocumentInfo.self, forKey: .document)
      let offset = try container.decode(Int.self, forKey: .offset)
      self = .format(document: document, offset: offset)
    case .typeContextInfo:
      let document = try container.decode(DocumentInfo.self, forKey: .document)
      let offset = try container.decode(Int.self, forKey: .offset)
      let args = try container.decode([String].self, forKey: .args)
      self = .typeContextInfo(document: document, offset: offset, args: args)
    case .conformingMethodList:
      let document = try container.decode(DocumentInfo.self, forKey: .document)
      let offset = try container.decode(Int.self, forKey: .offset)
      let typeList = try container.decode([String].self, forKey: .typeList)
      let args = try container.decode([String].self, forKey: .args)
      self = .conformingMethodList(document: document, offset: offset, typeList: typeList, args: args)
    case .collectExpressionType:
      let document = try container.decode(DocumentInfo.self, forKey: .document)
      let args = try container.decode([String].self, forKey: .args)
      self = .collectExpressionType(document: document, args: args)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .editorOpen(let document):
      try container.encode(BaseRequest.editorOpen, forKey: .request)
      try container.encode(document, forKey: .document)
    case .editorClose(let document):
      try container.encode(BaseRequest.editorClose, forKey: .request)
      try container.encode(document, forKey: .document)
    case .cursorInfo(let document, let offset, let args):
      try container.encode(BaseRequest.cursorInfo, forKey: .request)
      try container.encode(document, forKey: .document)
      try container.encode(offset, forKey: .offset)
      try container.encode(args, forKey: .args)
    case .codeComplete(let document, let offset, let args):
      try container.encode(BaseRequest.codeComplete, forKey: .request)
      try container.encode(document, forKey: .document)
      try container.encode(offset, forKey: .offset)
      try container.encode(args, forKey: .args)
    case .rangeInfo(let document, let offset, let length, let args):
      try container.encode(BaseRequest.rangeInfo, forKey: .request)
      try container.encode(document, forKey: .document)
      try container.encode(offset, forKey: .offset)
      try container.encode(length, forKey: .length)
      try container.encode(args, forKey: .args)
    case .semanticRefactoring(let document, let offset, let kind, let args):
      try container.encode(BaseRequest.semanticRefactoring, forKey: .request)
      try container.encode(document, forKey: .document)
      try container.encode(offset, forKey: .offset)
      try container.encode(kind, forKey: .kind)
      try container.encode(args, forKey: .args)
    case .editorReplaceText(let document, let offset, let length, let text):
      try container.encode(BaseRequest.replaceText, forKey: .request)
      try container.encode(document, forKey: .document)
      try container.encode(offset, forKey: .offset)
      try container.encode(length, forKey: .length)
      try container.encode(text, forKey: .text)
    case .format(let document, let offset):
      try container.encode(BaseRequest.format, forKey: .request)
      try container.encode(document, forKey: .document)
      try container.encode(offset, forKey: .offset)
    case .typeContextInfo(let document, let offset, let args):
      try container.encode(BaseRequest.typeContextInfo, forKey: .request)
      try container.encode(document, forKey: .document)
      try container.encode(offset, forKey: .offset)
      try container.encode(args, forKey: .args)
    case .conformingMethodList(let document, let offset, let typeList, let args):
      try container.encode(BaseRequest.conformingMethodList, forKey: .request)
      try container.encode(document, forKey: .document)
      try container.encode(offset, forKey: .offset)
      try container.encode(typeList, forKey: .typeList)
      try container.encode(args, forKey: .args)
    case .collectExpressionType(let document, let args):
      try container.encode(BaseRequest.collectExpressionType, forKey: .request)
      try container.encode(document, forKey: .document)
      try container.encode(args, forKey: .args)
    }
  }
}

extension RequestInfo: CustomStringConvertible {
  public var description: String {
    switch self {
    case .editorOpen(let document):
      return "EditorOpen on \(document)"
    case .editorClose(let document):
      return "EditorClose on \(document)"
    case .cursorInfo(let document, let offset, let args):
      return "CursorInfo in \(document) at offset \(offset) with args: \(args.joined(separator: " "))"
    case .rangeInfo(let document, let offset, let length, let args):
      return "RangeInfo in \(document) at offset \(offset) for length \(length) with args: \(args.joined(separator: " "))"
    case .codeComplete(let document, let offset, let args):
      return "CodeComplete in \(document) at offset \(offset) with args: \(args.joined(separator: " "))"
    case .semanticRefactoring(let document, let offset, let kind, let args):
      return "SemanticRefactoring (\(kind)) in \(document) at offset \(offset) with args: \(args.joined(separator: " "))"
    case .editorReplaceText(let document, let offset, let length, let text):
      return "ReplaceText in \(document) at offset \(offset) for length \(length) with text: \(text)"
    case .format(let document, let offset):
      return "Format in \(document) at offset \(offset)"
    case .typeContextInfo(let document, let offset, let args):
      return "TypeContextInfo in \(document) at offset \(offset) with args: \(args.joined(separator: " "))"
    case .conformingMethodList(let document, let offset, let typeList, let args):
      return "ConformingMethodList in \(document) at offset \(offset) conforming to \(typeList.joined(separator: ", ")) with args: \(args.joined(separator: " "))"
    case .collectExpressionType(let document, let args):
      return "CollectExpressionType in \(document) with args: \(args.joined(separator: " "))"
    }
  }
}

extension DocumentInfo: CustomStringConvertible {
  public var description: String {
    guard let modification = modification else {
      return path
    }
    return "\(path) (modified: \(modification.mode.rawValue))"
  }
}

extension SourceKitErrorReason: CustomStringConvertible {
  public var description: String {
    switch self {
    case .errorResponse:
      return "SourceKit returned an error response"
    case .errorTypeInResponse:
      return "SourceKit returned a response containing <<error type>>"
    case .errorDeserializingSyntaxTree:
      return "SourceKit returned a response with invalid SyntaxTree data"
    case .sourceAndSyntaxTreeMismatch:
      return "SourceKit returned a syntax tree that doesn't match the expected source"
    case .missingExpectedResult:
      return "SourceKit returned a response that didn't contain the expected result"
    }
  }
}

extension SourceKitResponseData: CustomStringConvertible {
  public var description: String {
    let response = results.isEmpty ? "<empty>" : results.joined(separator: ",\n")
    return """
    Response for \(request)
    -- begin response ------------
    \(response)
    -- end response --------------
    """
  }
}

extension SourceKitError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .crashed(let request):
      return """
        SourceKit crashed
          request: \(request)
        -- begin file content --------
        \(markSourceLocation(of: request) ?? "<unmodified>")
        -- end file content ----------
        """
    case .timedOut(let request):
      return """
        Timed out waiting for SourceKit response
          request: \(request)
        -- begin file content --------
        \(markSourceLocation(of: request) ?? "<unmodified>")
        -- end file content ----------
        """
    case .failed(let reason, let request, let response):
      return """
        \(reason)
          request: \(request)
          response: \(response)
        -- begin file content --------
        \(markSourceLocation(of: request) ?? "<unmodified>")
        -- end file content ----------
        """
    }
  }

  private func markSourceLocation(of request: RequestInfo) -> String? {
    switch request {
    case .editorOpen(let document):
      return document.modification?.content
    case .editorClose(let document):
      return document.modification?.content
    case .editorReplaceText(let document, let offset, let length, _):
      guard let source = document.modification?.content else { return nil }
      let startIndex = source.utf8.index(source.utf8.startIndex, offsetBy: offset)
      let endIndex = source.utf8.index(startIndex, offsetBy: length)
      let prefix = String(source.utf8.prefix(upTo: startIndex))!
      let replace = String(source.utf8.dropFirst(offset).prefix(length))!
      let suffix = String(source.utf8.suffix(from: endIndex))!
      return prefix + "<replace-start>" + replace + "<replace-end>" + suffix
    case .format(let document, let offset):
      guard let source = document.modification?.content else { return nil }
      let index = source.utf8.index(source.utf8.startIndex, offsetBy: offset)
      let prefix = String(source.utf8.prefix(upTo: index))!
      let suffix = String(source.utf8.suffix(from: index))!
      return prefix + "<format>" + suffix
    case .cursorInfo(let document, let offset, _):
      guard let source = document.modification?.content else { return nil }
      let index = source.utf8.index(source.utf8.startIndex, offsetBy: offset)
      let prefix = String(source.utf8.prefix(upTo: index))!
      let suffix = String(source.utf8.suffix(from: index))!
      return prefix + "<cursor-offset>" + suffix
    case .codeComplete(let document, let offset, _):
      guard let source = document.modification?.content else { return nil }
      let index = source.utf8.index(source.utf8.startIndex, offsetBy: offset)
      let prefix = String(source.utf8.prefix(upTo: index))!
      let suffix = String(source.utf8.suffix(from: index))!
      return prefix + "<complete-offset>" + suffix
    case .rangeInfo(let document, let offset, let length, _):
      guard let source = document.modification?.content else { return nil }
      let startIndex = source.utf8.index(source.utf8.startIndex, offsetBy: offset)
      let endIndex = source.utf8.index(startIndex, offsetBy: length)
      let prefix = String(source.utf8.prefix(upTo: startIndex))!
      let replace = String(source.utf8.dropFirst(offset).prefix(length))!
      let suffix = String(source.utf8.suffix(from: endIndex))!
      return prefix + "<range-start>" + replace + "<range-end>" + suffix
    case .semanticRefactoring(let document, let offset, _, _):
      guard let source = document.modification?.content else { return nil }
      let index = source.utf8.index(source.utf8.startIndex, offsetBy: offset)
      let prefix = String(source.utf8.prefix(upTo: index))!
      let suffix = String(source.utf8.suffix(from: index))!
      return prefix + "<refactor-offset>" + suffix
    case .typeContextInfo(let document, let offset, _):
      guard let source = document.modification?.content else { return nil }
      let index = source.utf8.index(source.utf8.startIndex, offsetBy: offset)
      let prefix = String(source.utf8.prefix(upTo: index))!
      let suffix = String(source.utf8.suffix(from: index))!
      return prefix + "<type-context-info-offset>" + suffix
    case .conformingMethodList(let document, let offset, _, _):
      guard let source = document.modification?.content else { return nil }
      let index = source.utf8.index(source.utf8.startIndex, offsetBy: offset)
      let prefix = String(source.utf8.prefix(upTo: index))!
      let suffix = String(source.utf8.suffix(from: index))!
      return prefix + "<conforming-method-list-offset>" + suffix
    case .collectExpressionType(let document, _):
      return document.modification?.content
    }
  }
}

extension StressTesterMessage: CustomStringConvertible {
  public var description: String {
    switch self {
    case .detected(let error):
      return "Failure detected: \(error)"
    case .produced(let responseData):
      return "Produced: \(responseData)"
    }
  }
}
