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

enum Action {
  case cursorInfo(offset: Int)
  case codeComplete(offset: Int)
  case rangeInfo(offset: Int, length: Int)
  case replaceText(offset: Int, length: Int, text: String)
}

extension Action: CustomStringConvertible {
  var description: String {
    switch self {
    case .cursorInfo(let offset):
      return "CusorInfo at offset \(offset)"
    case .codeComplete(let offset):
      return "CodeComplete at offset \(offset)"
    case .rangeInfo(let from, let length):
      return "RangeInfo from offset \(from) for length \(length)"
    case .replaceText(let from, let length, let text):
      return "ReplaceText from offset \(from) for length \(length) with \(text.debugDescription)"
    }
  }
}

extension Action: Codable {
  enum CodingKeys: String, CodingKey {
    case action, offset, length, text
  }
  enum BaseAction: String, Codable {
    case cursorInfo, codeComplete, rangeInfo, replaceText
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(BaseAction.self, forKey: .action) {
    case .cursorInfo:
      let offset = try container.decode(Int.self, forKey: .offset)
      self = .cursorInfo(offset: offset)
    case .codeComplete:
      let offset = try container.decode(Int.self, forKey: .offset)
      self = .codeComplete(offset: offset)
    case .rangeInfo:
      let offset = try container.decode(Int.self, forKey: .offset)
      let length = try container.decode(Int.self, forKey: .length)
      self = .rangeInfo(offset: offset, length: length)
    case .replaceText:
      let offset = try container.decode(Int.self, forKey: .offset)
      let length = try container.decode(Int.self, forKey: .length)
      let text = try container.decode(String.self, forKey: .text)
      self = .replaceText(offset: offset, length: length, text: text)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .cursorInfo(let offset):
      try container.encode(BaseAction.cursorInfo, forKey: .action)
      try container.encode(offset, forKey: .offset)
    case .codeComplete(let offset):
      try container.encode(BaseAction.codeComplete, forKey: .action)
      try container.encode(offset, forKey: .offset)
    case .rangeInfo(let startOffset, let length):
      try container.encode(BaseAction.rangeInfo, forKey: .action)
      try container.encode(startOffset, forKey: .offset)
      try container.encode(length, forKey: .length)
    case .replaceText(let offset, let length, let text):
      try container.encode(BaseAction.replaceText, forKey: .action)
      try container.encode(offset, forKey: .offset)
      try container.encode(length, forKey: .length)
      try container.encode(text, forKey: .text)
    }
  }
}
