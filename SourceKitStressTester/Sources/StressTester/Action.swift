//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public enum Action: Equatable {
  case cursorInfo(offset: Int)

  /// If expectedResult is non-nil, the results should contain expectedResult, otherwise the results should
  /// not be checked.
  case codeComplete(offset: Int, expectedResult: ExpectedResult?)
  case rangeInfo(offset: Int, length: Int)
  case replaceText(offset: Int, length: Int, text: String)
  case format(offset: Int)
  case typeContextInfo(offset: Int)
  case conformingMethodList(offset: Int)
  case collectExpressionType
}

extension Action: CustomStringConvertible {
  public var description: String {
    switch self {
    case .cursorInfo(let offset):
      return "CusorInfo at offset \(offset)"
    case .codeComplete(let offset, let expectedResult):
      return "CodeComplete at offset \(offset) with expectedResult \(expectedResult?.name.name ?? "None")"
    case .rangeInfo(let from, let length):
      return "RangeInfo from offset \(from) for length \(length)"
    case .replaceText(let from, let length, let text):
      return "ReplaceText from offset \(from) for length \(length) with \(text.debugDescription)"
    case .format(let offset):
      return "Format line containing offset \(offset)"
    case .typeContextInfo(let offset):
      return "TypeContextInfo at offset \(offset)"
    case .conformingMethodList(let offset):
      return "ConformingMethodList at offset \(offset)"
    case .collectExpressionType:
      return "CollectExpressionType"
    }
  }
}

extension Action: Codable {
  enum CodingKeys: String, CodingKey {
    case action, offset, length, text, expectedResult
  }
  public enum BaseAction: String, Codable {
    case cursorInfo, codeComplete, rangeInfo, replaceText, format,
      typeContextInfo, conformingMethodList, collectExpressionType
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(BaseAction.self, forKey: .action) {
    case .cursorInfo:
      let offset = try container.decode(Int.self, forKey: .offset)
      self = .cursorInfo(offset: offset)
    case .codeComplete:
      let offset = try container.decode(Int.self, forKey: .offset)
      let expectedResult = try container.decodeIfPresent(ExpectedResult.self, forKey: .expectedResult)
      self = .codeComplete(offset: offset, expectedResult: expectedResult)
    case .rangeInfo:
      let offset = try container.decode(Int.self, forKey: .offset)
      let length = try container.decode(Int.self, forKey: .length)
      self = .rangeInfo(offset: offset, length: length)
    case .replaceText:
      let offset = try container.decode(Int.self, forKey: .offset)
      let length = try container.decode(Int.self, forKey: .length)
      let text = try container.decode(String.self, forKey: .text)
      self = .replaceText(offset: offset, length: length, text: text)
    case .format:
      let offset = try container.decode(Int.self, forKey: .offset)
      self = .format(offset: offset)
    case .typeContextInfo:
      let offset = try container.decode(Int.self, forKey: .offset)
      self = .typeContextInfo(offset: offset)
    case .conformingMethodList:
      let offset = try container.decode(Int.self, forKey: .offset)
      self = .conformingMethodList(offset: offset)
    case .collectExpressionType:
      self = .collectExpressionType
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .cursorInfo(let offset):
      try container.encode(BaseAction.cursorInfo, forKey: .action)
      try container.encode(offset, forKey: .offset)
    case .codeComplete(let offset, let expectedResult):
      try container.encode(BaseAction.codeComplete, forKey: .action)
      try container.encode(offset, forKey: .offset)
      try container.encodeIfPresent(expectedResult, forKey: .expectedResult)
    case .rangeInfo(let startOffset, let length):
      try container.encode(BaseAction.rangeInfo, forKey: .action)
      try container.encode(startOffset, forKey: .offset)
      try container.encode(length, forKey: .length)
    case .replaceText(let offset, let length, let text):
      try container.encode(BaseAction.replaceText, forKey: .action)
      try container.encode(offset, forKey: .offset)
      try container.encode(length, forKey: .length)
      try container.encode(text, forKey: .text)
    case .format(let offset):
      try container.encode(BaseAction.format, forKey: .action)
      try container.encode(offset, forKey: .offset)
    case .typeContextInfo(let offset):
      try container.encode(BaseAction.typeContextInfo, forKey: .action)
      try container.encode(offset, forKey: .offset)
    case .conformingMethodList(let offset):
      try container.encode(BaseAction.conformingMethodList, forKey: .action)
      try container.encode(offset, forKey: .offset)
    case .collectExpressionType:
      try container.encode(BaseAction.collectExpressionType, forKey: .action)
    }
  }
}

public struct ExpectedResult: Codable, Equatable {
  public enum Kind: String, Codable { case reference, call, pattern }
  public let name: SwiftName
  public let kind: Kind

  public init(name: SwiftName, kind: Kind) {
    self.name = name
    self.kind = kind
  }
}

public struct SwiftName: Codable, Equatable {
  public let base: String
  public let argLabels: [String]
  public var name: String {
    argLabels.isEmpty
        ? base
        : "\(base)(\(argLabels.map{ "\($0.isEmpty ? "_" : $0):" }.joined()))"
  }

  public init?(_ name: String) {
    if let argStart = name.firstIndex(of: "(") {
      guard let argEnd = name.firstIndex(of: ")") else { return nil }
      base = String(name[..<argStart])
      argLabels = name[name.index(after: argStart)..<argEnd]
        .split(separator: ":", omittingEmptySubsequences: false)
        .dropLast()
        .map{ $0 == "_" ? "" : String($0)}
    } else {
      base = name
      argLabels = []
    }
  }

  init(base: String, labels: [String]) {
    self.base = base
    self.argLabels = labels.map{ $0 == "_" ? "" : $0 }
  }
}
