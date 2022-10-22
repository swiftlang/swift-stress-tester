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

import Common

public struct ExpectedIssue: Equatable, Codable {
  public let applicableConfigs: Set<String>
  public let issueUrl: String
  public let path: String
  public let modification: String?
  public let issueDetail: IssueDetail

  public init(applicableConfigs: Set<String>, issueUrl: String, path: String,
              modification: String?, issueDetail: IssueDetail) {
    self.applicableConfigs = applicableConfigs
    self.issueUrl = issueUrl
    self.path = path
    self.modification = modification
    self.issueDetail = issueDetail
  }

  /// Checks if this expected issue matches the given issue
  ///
  /// - parameters:
  ///   - issue: the issue to match against
  /// - returns: true if the issue matches
  public func matches(_ issue: StressTesterIssue) -> Bool {
    switch issue {
    case .failed(let sourceKitError, _):
      return matches(sourceKitError.request)
    case .errored(let status, let file, let arguments):
      guard case .stressTesterCrash(let xStatus, let xArguments) = issueDetail else { return false }
      return match(file, against: path) &&
        match(status, against: xStatus) &&
        match(arguments, against: xArguments)
    }
  }

  private func matches(_ info: RequestInfo) -> Bool {
    func matchDocument(_ doc: DocumentInfo) -> Bool {
      return match(doc.path, against: path) &&
        match(doc.modificationSummaryCode, against: modification)
    }

    switch info {
    case .editorOpen(let document):
      guard case .editorOpen = issueDetail else { return false }
      return matchDocument(document)
    case .editorClose(let document):
      guard case .editorClose = issueDetail else { return false }
      return matchDocument(document)
    case .editorReplaceText(let document, let offset, let length, let text):
      guard case .editorReplaceText(let specOffset, let specLength, let specText) = issueDetail else { return false }
      return matchDocument(document) &&
        match(offset, against: specOffset) &&
        match(length, against: specLength) &&
        match(text, against: specText)
    case .format(let document, let offset):
      guard case .format(let specOffset) = issueDetail else { return false }
      return matchDocument(document) &&
        match(offset, against: specOffset)
    case .cursorInfo(let document, let offset, _):
      guard case .cursorInfo(let specOffset) = issueDetail else { return false }
      return matchDocument(document) &&
        match(offset, against: specOffset)
    case .codeCompleteOpen(let document, let offset, _):
      guard case .codeCompleteOpen(let specOffset) = issueDetail else { return false }
      return matchDocument(document) &&
        match(offset, against: specOffset)
    case .codeCompleteUpdate(let document, let offset, _):
      guard case .codeCompleteUpdate(let specOffset) = issueDetail else { return false }
      return matchDocument(document) &&
        match(offset, against: specOffset)
    case .codeCompleteClose(let document, let offset):
      guard case .codeCompleteClose(let specOffset) = issueDetail else { return false }
      return matchDocument(document) &&
        match(offset, against: specOffset)
    case .rangeInfo(let document, let offset, let length, _):
      guard case .rangeInfo(let specOffset, let specLength) = issueDetail else { return false }
      return matchDocument(document) &&
        match(offset, against: specOffset) &&
        match(length, against: specLength)
    case .semanticRefactoring(let document, let offset, let refactoring, _):
      guard case .semanticRefactoring(let specOffset, let specRefactoring) = issueDetail else { return false }
      return matchDocument(document) &&
        match(offset, against: specOffset) &&
        match(refactoring, against: specRefactoring)
    case .typeContextInfo(let document, let offset, _):
      guard case .typeContextInfo(let specOffset) = issueDetail else { return false }
      return matchDocument(document) &&
        match(offset, against: specOffset)
    case .conformingMethodList(let document, let offset, _, _):
      guard case .conformingMethodList(let specOffset) = issueDetail else { return false }
      return matchDocument(document) &&
        match (offset, against: specOffset)
    case .collectExpressionType(let document, _):
      guard case .collectExpressionType = issueDetail else { return false }
      return matchDocument(document)
    case .writeModule(let document, _):
      guard case .writeModule = issueDetail else { return false }
      return matchDocument(document)
    case .interfaceGen(let document, _, _):
      guard case .interfaceGen = issueDetail else { return false }
      return matchDocument(document)
    case .statistics:
      return false
    }
  }

  /// Checks whether this expected failure could match a request made in the
  /// given file path
  func isApplicable(toPath path: String) -> Bool {
    return match(path, against: self.path)
  }

  private func match<T: Equatable>(_ input: T?, against specification: T?) -> Bool {
    guard let specification = specification else { return true }
    guard let input = input else { return false }
    return input == specification
  }

  private func match(_ input: String?, against specification: String?) -> Bool {
    guard let specification = specification else { return true }
    guard let input = input else { return false }
    guard specification.contains("*") else { return input == specification }

    let parts = specification.split(separator: "*")
    guard !parts.isEmpty else { return true }

    let anchoredStart = !specification.hasPrefix("*")
    let anchoredEnd = !specification.hasSuffix("*")
    var remaining = Substring(input)

    for (offset, part) in parts.enumerated() {
      guard let match = remaining.range(of: part, options: [.caseInsensitive]) else {
        return false
      }
      if offset == 0 && anchoredStart && match.lowerBound != input.startIndex {
        return false
      }
      if offset == parts.endIndex - 1 && anchoredEnd && match.upperBound != input.endIndex {
        return false
      }
      remaining = remaining[match.upperBound...]
    }
    return true
  }
}

public extension ExpectedIssue {

  init(matching stressTesterIssue: StressTesterIssue, issueUrl: String, config: String) {
    self.issueUrl = issueUrl
    self.applicableConfigs = [config]

    switch stressTesterIssue {
    case .errored(let status, let file, let arguments):
      path = file
      modification = nil
      issueDetail = .stressTesterCrash(status: status, arguments: arguments)
    case .failed(let failure, _):
      switch failure.request {
      case .editorOpen(let document):
        path = document.path
        modification = document.modificationSummaryCode
        issueDetail = .editorOpen
      case .editorClose(let document):
        path = document.path
        modification = document.modificationSummaryCode
        issueDetail = .editorClose
      case .editorReplaceText(let document, let offset, let length, let text):
        path = document.path
        modification = document.modificationSummaryCode
        issueDetail = .editorReplaceText(offset: offset, length: length, text: text)
      case .cursorInfo(let document, let offset, _):
        path = document.path
        modification = document.modificationSummaryCode
        issueDetail = .cursorInfo(offset: offset)
      case .format(let document, let offset):
        path = document.path
        modification = document.modificationSummaryCode
        issueDetail = .format(offset: offset)
      case .codeCompleteOpen(let document, let offset, _):
        path = document.path
        modification = document.modificationSummaryCode
        issueDetail = .codeCompleteOpen(offset: offset)
      case .codeCompleteUpdate(let document, let offset, _):
        path = document.path
        modification = document.modificationSummaryCode
        issueDetail = .codeCompleteUpdate(offset: offset)
      case .codeCompleteClose(let document, let offset):
        path = document.path
        modification = document.modificationSummaryCode
        issueDetail = .codeCompleteClose(offset: offset)
      case .rangeInfo(let document, let offset, let length, _):
        path = document.path
        modification = document.modificationSummaryCode
        issueDetail = .rangeInfo(offset: offset, length: length)
      case .semanticRefactoring(let document, let offset, let refactoring, _):
        path = document.path
        modification = document.modificationSummaryCode
        issueDetail = .semanticRefactoring(offset: offset, refactoring: refactoring)
      case .typeContextInfo(let document, let offset, _):
        path = document.path
        modification = document.modificationSummaryCode
        issueDetail = .typeContextInfo(offset: offset)
      case .conformingMethodList(let document, let offset, _, _):
        path = document.path
        modification = document.modificationSummaryCode
        issueDetail = .conformingMethodList(offset: offset)
      case .collectExpressionType(let document, _):
        path = document.path
        modification = document.modificationSummaryCode
        issueDetail = .collectExpressionType
      case .writeModule(let document, _):
        path = document.path
        modification = document.modificationSummaryCode
        issueDetail = .writeModule
      case .interfaceGen(let document, _, _):
        path = document.path
        modification = document.modificationSummaryCode
        issueDetail = .interfaceGen
      case .statistics:
        path = "<statistics>"
        modification = nil
        issueDetail = .statistics
      }
    }
  }

  enum IssueDetail: Equatable, Codable {
    case editorOpen
    case editorClose
    case editorReplaceText(offset: Int?, length: Int?, text: String?)
    case cursorInfo(offset: Int?)
    case format(offset: Int?)
    case codeCompleteOpen(offset: Int?)
    case codeCompleteUpdate(offset: Int?)
    case codeCompleteClose(offset: Int?)
    case rangeInfo(offset: Int?, length: Int?)
    case typeContextInfo(offset: Int?)
    case conformingMethodList(offset: Int?)
    case collectExpressionType
    case writeModule
    case interfaceGen
    case semanticRefactoring(offset: Int?, refactoring: String?)
    case stressTesterCrash(status: Int32?, arguments: String?)
    case statistics

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      switch try container.decode(RequestBase.self, forKey: .kind) {
      case .editorOpen:
        self = .editorOpen
      case .editorClose:
        self = .editorClose
      case .editorReplaceText:
        self = .editorReplaceText(
          offset: try container.decodeIfPresent(Int.self, forKey: .offset),
          length: try container.decodeIfPresent(Int.self, forKey: .length),
          text: try container.decodeIfPresent(String.self, forKey: .text)
        )
      case .cursorInfo:
        self = .cursorInfo(
          offset: try container.decodeIfPresent(Int.self, forKey: .offset)
        )
      case .format:
        self = .format(
          offset: try container.decodeIfPresent(Int.self, forKey: .offset)
        )
      case .codeComplete:
        self = .codeCompleteOpen(
          offset: try container.decodeIfPresent(Int.self, forKey: .offset)
        )
      case .codeCompleteUpdate:
        self = .codeCompleteUpdate(
          offset: try container.decodeIfPresent(Int.self, forKey: .offset)
        )
      case .codeCompleteClose:
        self = .codeCompleteClose(
          offset: try container.decodeIfPresent(Int.self, forKey: .offset)
        )
      case .rangeInfo:
        self = .rangeInfo(
          offset: try container.decodeIfPresent(Int.self, forKey: .offset),
          length: try container.decodeIfPresent(Int.self, forKey: .length)
        )
      case .semanticRefactoring:
        self = .semanticRefactoring(
          offset: try container.decodeIfPresent(Int.self, forKey: .offset),
          refactoring: try container.decodeIfPresent(String.self, forKey: .refactoring)
        )
      case .stressTesterCrash:
        self = .stressTesterCrash(
          status: try container.decodeIfPresent(Int32.self, forKey: .status),
          arguments: try container.decodeIfPresent(String.self, forKey: .arguments))
      case .typeContextInfo:
        self = .typeContextInfo(
          offset: try container.decodeIfPresent(Int.self, forKey: .offset)
        )
      case .conformingMethodList:
        self = .conformingMethodList(
          offset: try container.decodeIfPresent(Int.self, forKey: .offset)
        )
      case .collectExpressionType:
        self = .collectExpressionType
      case .writeModule:
        self = .writeModule
      case .interfaceGen:
        self = .interfaceGen
      case .statistics:
        self = .statistics
      }
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      switch self {
      case .editorOpen:
        try container.encode(RequestBase.editorOpen, forKey: .kind)
      case .editorClose:
        try container.encode(RequestBase.editorClose, forKey: .kind)
      case .editorReplaceText(let offset, let length, let text):
        try container.encode(RequestBase.editorReplaceText, forKey: .kind)
        try container.encode(offset, forKey: .offset)
        try container.encode(length, forKey: .length)
        try container.encode(text, forKey: .text)
      case .cursorInfo(let offset):
        try container.encode(RequestBase.cursorInfo, forKey: .kind)
        try container.encode(offset, forKey: .offset)
      case .format(let offset):
        try container.encode(RequestBase.format, forKey: .kind)
        try container.encode(offset, forKey: .offset)
      case .codeCompleteOpen(let offset):
        try container.encode(RequestBase.codeComplete, forKey: .kind)
        try container.encode(offset, forKey: .offset)
      case .codeCompleteUpdate(let offset):
        try container.encode(RequestBase.codeCompleteUpdate, forKey: .kind)
        try container.encode(offset, forKey: .offset)
      case .codeCompleteClose(let offset):
        try container.encode(RequestBase.codeCompleteClose, forKey: .kind)
        try container.encode(offset, forKey: .offset)
      case .rangeInfo(let offset, let length):
        try container.encode(RequestBase.rangeInfo, forKey: .kind)
        try container.encode(offset, forKey: .offset)
        try container.encode(length, forKey: .length)
      case .semanticRefactoring(let offset, let refactoring):
        try container.encode(RequestBase.semanticRefactoring, forKey: .kind)
        try container.encode(offset, forKey: .offset)
        try container.encode(refactoring, forKey: .refactoring)
      case .stressTesterCrash(let status, let arguments):
        try container.encode(RequestBase.stressTesterCrash, forKey: .kind)
        try container.encode(status, forKey: .status)
        try container.encode(arguments, forKey: .arguments)
      case .typeContextInfo(let offset):
        try container.encode(RequestBase.typeContextInfo, forKey: .kind)
        try container.encode(offset, forKey: .offset)
      case .conformingMethodList(let offset):
        try container.encode(RequestBase.conformingMethodList, forKey: .kind)
        try container.encode(offset, forKey: .offset)
      case .collectExpressionType:
        try container.encode(RequestBase.collectExpressionType, forKey: .kind)
      case .writeModule:
        try container.encode(RequestBase.writeModule, forKey: .kind)
      case .interfaceGen:
        try container.encode(RequestBase.interfaceGen, forKey: .kind)
      case .statistics:
        try container.encode(RequestBase.statistics, forKey: .kind)
      }
    }

    private enum CodingKeys: String, CodingKey {
      case kind, offset, length, text, refactoring, status, arguments
    }

    private enum RequestBase: String, Codable {
      case editorOpen
      case editorClose
      case editorReplaceText
      case cursorInfo
      case codeComplete
      case codeCompleteUpdate
      case codeCompleteClose
      case rangeInfo
      case semanticRefactoring
      case typeContextInfo
      case conformingMethodList
      case collectExpressionType
      case format
      case writeModule
      case interfaceGen
      case statistics
      case stressTesterCrash
    }

    func enabledFor(request: RequestKind) -> Bool {
      switch self {
      case .editorOpen:
        return true
      case .editorClose:
        return true
      case .editorReplaceText:
        return true
      case .cursorInfo:
        return request == .cursorInfo
      case .format:
        return request == .format
      case .codeCompleteOpen:
        return request == .codeComplete
      case .codeCompleteUpdate:
        return request == .codeCompleteUpdate
      case .codeCompleteClose:
        return request == .codeCompleteClose
      case .rangeInfo:
        return request == .rangeInfo
      case .typeContextInfo:
        return request == .typeContextInfo
      case .conformingMethodList:
        return request == .conformingMethodList
      case .collectExpressionType:
        return request == .collectExpressionType
      case .writeModule:
        return request == .testModule
      case .interfaceGen:
        return request == .testModule
      case .semanticRefactoring:
        return request == .cursorInfo || request == .rangeInfo
      case .stressTesterCrash:
        return true
      case .statistics:
        return true
      }
    }
  }
}
