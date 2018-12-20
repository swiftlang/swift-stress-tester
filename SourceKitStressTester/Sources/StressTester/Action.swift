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

enum Action: Equatable {
  case cursorInfo(position: SourcePosition)
  case codeComplete(position: SourcePosition)
  case rangeInfo(range: SourceRange)
  case replaceText(range: SourceRange, text: String)
}

struct SourcePosition: Equatable, Codable {
  let offset: Int
  let line: Int
  let column: Int
}

struct SourceRange: Equatable, Codable {
  let start: SourcePosition
  let end: SourcePosition
  let length: Int
  var offset: Int { return start.offset }
  var endOffset: Int { return start.offset + length }
  var isEmpty: Bool { return length == 0 }
}

extension Action: CustomStringConvertible {
  var description: String {
    switch self {
    case .cursorInfo(let position):
      return "CusorInfo at \(position.line):\(position.column)"
    case .codeComplete(let position):
      return "CodeComplete at \(position.line):\(position.column)"
    case .rangeInfo(let range):
      return "RangeInfo from \(range.start.line):\(range.start.column) to \(range.end.line):\(range.end.column)"
    case .replaceText(let range, let text):
      return "ReplaceText from \(range.start.line):\(range.start.column) to \(range.end.line):\(range.end.column) with \(text.debugDescription)"
    }
  }
}

extension Action: Codable {
  enum CodingKeys: String, CodingKey {
    case action, position, range, text
  }
  enum BaseAction: String, Codable {
    case cursorInfo, codeComplete, rangeInfo, replaceText
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(BaseAction.self, forKey: .action) {
    case .cursorInfo:
      let position = try container.decode(SourcePosition.self, forKey: .position)
      self = .cursorInfo(position: position)
    case .codeComplete:
      let position = try container.decode(SourcePosition.self, forKey: .position)
      self = .codeComplete(position: position)
    case .rangeInfo:
      let range = try container.decode(SourceRange.self, forKey: .range)
      self = .rangeInfo(range: range)
    case .replaceText:
      let range = try container.decode(SourceRange.self, forKey: .range)
      let text = try container.decode(String.self, forKey: .text)
      self = .replaceText(range: range, text: text)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .cursorInfo(let position):
      try container.encode(BaseAction.cursorInfo, forKey: .action)
      try container.encode(position, forKey: .position)
    case .codeComplete(let position):
      try container.encode(BaseAction.codeComplete, forKey: .action)
      try container.encode(position, forKey: .position)
    case .rangeInfo(let range):
      try container.encode(BaseAction.rangeInfo, forKey: .action)
      try container.encode(range, forKey: .range)
    case .replaceText(let range, let text):
      try container.encode(BaseAction.replaceText, forKey: .action)
      try container.encode(range, forKey: .range)
      try container.encode(text, forKey: .text)
    }
  }
}
