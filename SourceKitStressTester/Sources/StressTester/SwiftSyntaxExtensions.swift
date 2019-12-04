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

extension SyntaxProtocol {
  var ancestors: SyntaxAncestors {
    return SyntaxAncestors(Syntax(self))
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
    return parent.isProtocol(ExprSyntaxProtocol.self) ||
      parent.isProtocol(TypeSyntaxProtocol.self) ||
      parent.is(TupleExprElementSyntax.self)
  }

  var textWithoutBackticks: String {
    guard text.first == "`" && text.last == "`" else { return text }
    return String(text.dropFirst().dropLast())
  }

  var isLiteralExprClose: Bool {
    guard let parent = parent else {
      return false
    }
    switch self.tokenKind {
    case .rightParen:
      return parent.is(TupleExprSyntax.self)
    case .rightBrace:
      return parent.is(ClosureExprSyntax.self)
    case .rightSquareBracket:
      return parent.is(ArrayExprSyntax.self) || parent.is(DictionaryExprSyntax.self)
    default:
      return false
    }
  }
}
