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
    case .failed(let sourceKitError):
      return matches(sourceKitError.request)
    case .errored(let status, let file, let arguments):
      guard case .stressTesterCrash(let xStatus, let xArguments) = issueDetail else { return false }
      return match(file, against: path) &&
        match(status, against: xStatus) &&
        match(arguments, against: xArguments)
    }
  }

  private func matches(_ info: RequestInfo) -> Bool {
    switch info {
    case .editorOpen(let document):
      guard case .editorOpen = issueDetail else { return false }
      return match(document.path, against: path) &&
        match(document.modification?.summaryCode, against: modification)
    case .editorClose(let document):
      guard case .editorClose = issueDetail else { return false }
      return match(document.path, against: path) &&
        match(document.modification?.summaryCode, against: modification)
    case .editorReplaceText(let document, let offset, let length, let text):
      guard case .editorReplaceText(let specOffset, let specLength, let specText) = issueDetail else { return false }
      return match(document.path, against: path) &&
        match(document.modification?.summaryCode, against: modification) &&
        match(offset, against: specOffset) &&
        match(length, against: specLength) &&
        match(text, against: specText)
    case .format(let document, let offset):
      guard case .format(let specOffset) = issueDetail else { return false }
      return match(document.path, against: path) &&
        match(document.modification?.summaryCode, against: modification) &&
        match(offset, against: specOffset)
    case .cursorInfo(let document, let offset, _):
      guard case .cursorInfo(let specOffset) = issueDetail else { return false }
      return match(document.path, against: path) &&
        match(document.modification?.summaryCode, against: modification) &&
        match(offset, against: specOffset)
    case .codeComplete(let document, let offset, _):
      guard case .codeComplete(let specOffset) = issueDetail else { return false }
      return match(document.path, against: path) &&
        match(document.modification?.summaryCode, against: modification) &&
        match(offset, against: specOffset)
    case .rangeInfo(let document, let offset, let length, _):
      guard case .rangeInfo(let specOffset, let specLength) = issueDetail else { return false }
      return match(document.path, against: path) &&
        match(document.modification?.summaryCode, against: modification) &&
        match(offset, against: specOffset) &&
        match(length, against: specLength)
    case .semanticRefactoring(let document, let offset, let refactoring, _):
      guard case .semanticRefactoring(let specOffset, let specRefactoring) = issueDetail else { return false }
      return match(document.path, against: path) &&
        match(document.modification?.summaryCode, against: modification) &&
        match(offset, against: specOffset) &&
        match(refactoring, against: specRefactoring)
    case .typeContextInfo(let document, let offset, _):
      guard case .typeContextInfo(let specOffset) = issueDetail else { return false }
      return match(document.path, against: path) &&
        match(document.modification?.summaryCode, against: modification) &&
        match(offset, against: specOffset)
    case .conformingMethodList(let document, let offset, _, _):
      guard case .conformingMethodList(let specOffset) = issueDetail else { return false }
      return match(document.path, against: path) &&
        match (document.modification?.summaryCode, against: modification) &&
        match (offset, against: specOffset)
    case .collectExpressionType(let document, _):
      guard case .collectExpressionType = issueDetail else { return false }
      return match(document.path, against: path) &&
        match (document.modification?.summaryCode, against: modification)
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
    case .failed(let failure):
      switch failure.request {
      case .editorOpen(let document):
        path = document.path
        modification = document.modification?.summaryCode
        issueDetail = .editorOpen
      case .editorClose(let document):
        path = document.path
        modification = document.modification?.summaryCode
        issueDetail = .editorClose
      case .editorReplaceText(let document, let offset, let length, let text):
        path = document.path
        modification = document.modification?.summaryCode
        issueDetail = .editorReplaceText(offset: offset, length: length, text: text)
      case .cursorInfo(let document, let offset, _):
        path = document.path
        modification = document.modification?.summaryCode
        issueDetail = .cursorInfo(offset: offset)
      case .format(let document, let offset):
        path = document.path
        modification = document.modification?.summaryCode
        issueDetail = .format(offset: offset)
      case .codeComplete(let document, let offset, _):
        path = document.path
        modification = document.modification?.summaryCode
        issueDetail = .codeComplete(offset: offset)
      case .rangeInfo(let document, let offset, let length, _):
        path = document.path
        modification = document.modification?.summaryCode
        issueDetail = .rangeInfo(offset: offset, length: length)
      case .semanticRefactoring(let document, let offset, let refactoring, _):
        path = document.path
        modification = document.modification?.summaryCode
        issueDetail = .semanticRefactoring(offset: offset, refactoring: refactoring)
      case .typeContextInfo(let document, let offset, _):
        path = document.path
        modification = document.modification?.summaryCode
        issueDetail = .typeContextInfo(offset: offset)
      case .conformingMethodList(let document, let offset, _, _):
        path = document.path
        modification = document.modification?.summaryCode
        issueDetail = .conformingMethodList(offset: offset)
      case .collectExpressionType(let document, _):
        path = document.path
        modification = document.modification?.summaryCode
        issueDetail = .collectExpressionType
      }
    }
  }

  enum IssueDetail: Equatable, Codable {
    case editorOpen
    case editorClose
    case editorReplaceText(offset: Int?, length: Int?, text: String?)
    case cursorInfo(offset: Int?)
    case format(offset: Int?)
    case codeComplete(offset: Int?)
    case rangeInfo(offset: Int?, length: Int?)
    case typeContextInfo(offset: Int?)
    case conformingMethodList(offset: Int?)
    case collectExpressionType
    case semanticRefactoring(offset: Int?, refactoring: String?)
    case stressTesterCrash(status: Int32?, arguments: String?)

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
        self = .codeComplete(
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
      case .codeComplete(let offset):
        try container.encode(RequestBase.codeComplete, forKey: .kind)
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
      }
    }

    private enum CodingKeys: String, CodingKey {
      case kind, offset, length, text, refactoring, status, arguments
    }

    private enum RequestBase: String, Codable {
      case editorOpen, editorClose, editorReplaceText
      case cursorInfo, codeComplete, rangeInfo, semanticRefactoring, typeContextInfo, conformingMethodList, collectExpressionType, format
      case stressTesterCrash
    }
  }
}
