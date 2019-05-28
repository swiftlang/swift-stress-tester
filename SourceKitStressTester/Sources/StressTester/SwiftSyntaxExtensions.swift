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

import SwiftSyntax

struct SyntaxAncestorIterator: IteratorProtocol {
  private var node: Syntax

  fileprivate init(_ node: Syntax) {
      self.node = node
  }

  mutating func next() -> Syntax? {
    if let parent = node.parent {
      node = parent
      return node
    }
    return nil
  }
}

struct SyntaxAncestors: Sequence {
  private let node: Syntax

  fileprivate init(_ node: Syntax) {
    self.node = node
  }

  func makeIterator() -> SyntaxAncestorIterator {
      return SyntaxAncestorIterator(node)
  }
}

extension Syntax {
  var ancestors: SyntaxAncestors {
    return SyntaxAncestors(self)
  }
}

extension TokenSyntax {
  var isOperator: Bool {
    switch tokenKind {
    case .prefixOperator, .postfixOperator, .spacedBinaryOperator, .unspacedBinaryOperator, .equal:
      return true
    default:
      return false
    }
  }

  var pieces: (leadingTrivia: String, content: String, trailingTrivia: String) {
    let text = description.utf8
    let leadingTrivia = String(text.prefix(leadingTriviaLength.utf8Length))!
    let content = String(text.dropFirst(leadingTriviaLength.utf8Length).dropLast(trailingTriviaLength.utf8Length))!
    let trailingTrivia = String(text.suffix(trailingTriviaLength.utf8Length))!
    return (leadingTrivia, content, trailingTrivia)
  }

  var isIdentifier: Bool {
    switch tokenKind {
    case .identifier: fallthrough
    case .dollarIdentifier:
      return true
    default:
      return false
    }
  }

  var isReference: Bool {
    guard isIdentifier else { return false }
    guard let parent = parent else { return false }

    return parent.isExpr || parent.isType
  }

  var isLiteralExprClose: Bool {
    switch self.tokenKind {
    case .rightParen:
      return parent is TupleExprSyntax
    case .rightBrace:
      return parent is ClosureExprSyntax
    case .rightSquareBracket:
      return parent is ArrayExprSyntax || parent is DictionaryExprSyntax
    default:
      return false
    }
  }
}
