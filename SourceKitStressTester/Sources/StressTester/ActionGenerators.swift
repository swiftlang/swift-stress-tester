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
import SwiftSyntax

protocol ActionGenerator {
  func generate(for tree: SourceFileSyntax) -> [Action]
}

extension ActionGenerator {
  /// Entrypoint intended for testing purposes only
  func generate(for file: URL) -> [Action] {
    let tree = try! SyntaxParser.parse(file)
    return generate(for: tree)
  }

  fileprivate func generateActions(for token: TokenSyntax,
                                   at position: AbsolutePosition? = nil,
                                   withReplaceTexts: Bool = true,
                                   parentsAreValid: Bool = false,
                                   hasBoundaryBefore: Bool = true,
                                   hasBoundaryAfter: Bool = true) -> [Action] {
    precondition(position == nil || !parentsAreValid)

    let pieces = token.decomposed(at: position)
    var actions = [Action]()

    if !pieces.leadingTrivia.isEmpty, withReplaceTexts {
      actions.append(.replaceText(offset: pieces.triviaStart, length: 0, text: pieces.leadingTrivia))
    }

    if token.isReference, hasBoundaryBefore {
      actions.append(contentsOf: [
        .codeComplete(offset: pieces.contentStart),
        .typeContextInfo(offset: pieces.contentStart),
        .conformingMethodList(offset: pieces.contentStart)
      ])
    }
    if withReplaceTexts {
      actions.append(.replaceText(offset: pieces.contentStart, length: 0, text: pieces.content))
      if token.isIdentifier {
        actions.append(.collectExpressionType)
      }
    }

    if token.isIdentifier {
      actions.append(.cursorInfo(offset: pieces.contentStart))
      if hasBoundaryAfter {
        actions.append(contentsOf: [
          .codeComplete(offset: pieces.contentEnd),
          .typeContextInfo(offset: pieces.contentEnd),
          .conformingMethodList(offset: pieces.contentEnd)
        ])
      }
    } else if token.isLiteralExprClose {
      actions.append(contentsOf: [
        .codeComplete(offset: pieces.contentEnd),
        .typeContextInfo(offset: pieces.contentEnd),
        .conformingMethodList(offset: pieces.contentEnd)
      ])
    }

    if parentsAreValid {
      var node: Syntax = token
      while let parent = node.parent, !(parent is SourceFileSyntax),
        parent.endPositionBeforeTrailingTrivia == node.endPositionBeforeTrailingTrivia,
        parent.positionAfterSkippingLeadingTrivia != node.positionAfterSkippingLeadingTrivia {
          actions.append(.rangeInfo(offset: parent.positionAfterSkippingLeadingTrivia.utf8Offset, length: parent.contentLength.utf8Length))
          node = parent
      }
    }

    if !pieces.trailingTrivia.isEmpty, withReplaceTexts {
      actions.append(.replaceText(offset: pieces.contentEnd, length: 0, text: pieces.trailingTrivia))
    }

    return actions
  }

  /// - returns: true if the two tokens would combine when placed adjacent to
  /// one another
  fileprivate func willCombine(_ first: TokenSyntax?, _ second: TokenSyntax?) -> Bool {
    guard let first = first, let second = second, first.trailingTrivia.isEmpty && second.leadingTrivia.isEmpty else { return true }

    for tokenKind in [first.tokenKind, second.tokenKind] {
      switch tokenKind {
      case .leftParen: fallthrough
      case .rightParen: fallthrough
      case .leftBrace: fallthrough
      case .rightBrace: fallthrough
      case .leftSquareBracket: fallthrough
      case .rightSquareBracket: fallthrough
      case .leftAngle: fallthrough
      case .rightAngle: fallthrough
      case .period: fallthrough
      case .prefixPeriod: fallthrough
      case .comma: fallthrough
      case .colon: fallthrough
      case .semicolon: fallthrough
      case .equal: fallthrough
      case .pound: fallthrough
      case .prefixAmpersand: fallthrough
      case .arrow: fallthrough
      case .backtick: fallthrough
      case .backslash: fallthrough
      case .exclamationMark: fallthrough
      case .postfixQuestionMark: fallthrough
      case .infixQuestionMark: fallthrough
      case .stringQuote: fallthrough
      case .multilineStringQuote: fallthrough
      case .stringLiteral: fallthrough
      case .stringInterpolationAnchor:
        return false
      default:
        continue
      }
    }
    return true
  }
}

/// Walks through the provided source files token by token, generating
/// CursorInfo, RangeInfo, and CodeComplete actions as it goes.
final class RequestActionGenerator: SyntaxVisitor, ActionGenerator {
  var actions = [Action]()

  func generate(for tree: SourceFileSyntax) -> [Action] {
    actions.removeAll()
    var visitor = self
    tree.walk(&visitor)
    actions.append(.collectExpressionType)
    return actions
  }

  func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
    actions.append(contentsOf: generateActions(for: token, withReplaceTexts: false, parentsAreValid: true))
    return .visitChildren
  }
}

/// Works through the provided source files generating actions to first remove their
/// content, and then add it back again token by token. CursorInfo, RangeInfo and
/// CodeComplete actions are also emitted at applicable locations.
final class RewriteActionGenerator: SyntaxVisitor, ActionGenerator {
  var actions = [Action]()

  func generate(for tree: SourceFileSyntax) -> [Action] {
    actions = [.replaceText(offset: 0, length: tree.totalLength.utf8Length, text: "")]
    var visitor = self
    tree.walk(&visitor)
    return actions
  }

  func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
    actions.append(contentsOf: generateActions(for: token, withReplaceTexts: true, parentsAreValid: true))
    return .visitChildren
  }
}

final class ConcurrentRewriteActionGenerator: ActionGenerator {
  var actions = [Action]()

  func generate(for tree: SourceFileSyntax) -> [Action] {
    // clear the file contents
    actions = [.replaceText(offset: 0, length: tree.totalLength.utf8Length, text: "")]

    var groupedTokens = tree.statements.map { (length: SourceLength.zero, remaining: TokenData(of: $0).tokens[...]) }
    var tokensRemain = true

    while tokensRemain {
      tokensRemain = false

      var position = AbsolutePosition(utf8Offset: 0)
      groupedTokens = groupedTokens.map { group in
        position += group.length
        guard let next = group.remaining.first else { return group }

        let tokenLength = next.totalLength
        actions.append(contentsOf: generateActions(for: next, at: position))
        position += tokenLength
        tokensRemain = tokensRemain || group.remaining.count > 1
        return (length: group.length + tokenLength, remaining: group.remaining.dropFirst())
      }
    }

    return actions
  }
}


/// Works through the given source files, first removing their content, then
/// re-introducing it token by token, from the most deeply nested token to the
/// least. CursorInfo, and CodeComplete actions are also emitted along the way.
final class InsideOutRewriteActionGenerator: ActionGenerator {
  var actions = [Action]()

  func generate(for tree: SourceFileSyntax) -> [Action] {
    // clear the file contents
    actions = [.replaceText(offset: 0, length: tree.totalLength.utf8Length, text: "")]

    // compute the index to insert each token at, given we want to insert the most deeply
    // nested tokens first into a flat token list and end up with the tokens in their original
    // source order.
    let tokenData = TokenData(of: tree)
    var seenByDepth = [Int: Int]()
    let insertions = tokenData.tokens.map { token -> (TokenSyntax, Int) in
      let depth = tokenData.depths[token]!
      let insertionIndex = seenByDepth[depth] ?? 0
      for depth in 0...depth {
        seenByDepth[depth] = (seenByDepth[depth] ?? 0) + 1
      }
      return (token, insertionIndex)
    }

    // work through the tokens from the most deeply nested to the least,
    // inserting them into a token list at the indices computed above
    var worklist = [(token: TokenSyntax, endPos: AbsolutePosition)]()
    let fileStart = AbsolutePosition(utf8Offset: 0)
    for depth in seenByDepth.keys.sorted(by: >) {
      var lastInsertion: (endPos: AbsolutePosition, nextIndex: Int)? = nil
      for (token, index) in insertions where tokenData.depths[token] == depth {
        let fromIndex = lastInsertion?.nextIndex ?? 0
        let initialPos = lastInsertion?.endPos ?? fileStart
        let position = worklist[fromIndex..<index].reduce(initialPos) {
          $0 + $1.token.totalLength
        }

        let endPos = position + token.totalLength
        worklist.insert((token, endPos), at: index)
        lastInsertion = (endPos, index + 1)

        let previousToken = worklist.indices.contains(index-1) ? worklist[index-1].token : nil
        let nextToken = worklist.indices.contains(index+1) ? worklist[index+1].token : nil
        actions.append(contentsOf: generateActions(for: token, at: position,
                                                   withReplaceTexts: true,
                                                   parentsAreValid: false,
                                                   hasBoundaryBefore: !willCombine(previousToken, token),
                                                   hasBoundaryAfter: !willCombine(token, nextToken)))
      }
    }

    return actions
  }
}

/// Collects tokens and their depths within a given Syntax
fileprivate final class TokenData: SyntaxAnyVisitor {
  private(set) var tokens = [TokenSyntax]()
  private(set) var depths = [TokenSyntax: Int]()
  private var depth = -1

  init(of syntax: Syntax) {
    var visitor = self
    syntax.walk(&visitor)
  }

  func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
    depth += 1
    return .visitChildren
  }

  func visitAnyPost(_ node: Syntax) {
    depth -= 1
  }

  func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
    tokens.append(token)
    depths[token] = depth
    return visitAny(token)
  }
}

fileprivate struct DecomposedToken {
  let triviaStart: Int
  let contentStart: Int
  let contentEnd: Int
  let triviaEnd: Int

  let leadingTrivia: String
  let content: String
  let trailingTrivia: String

  init(from token: TokenSyntax, at position: AbsolutePosition) {
    self.triviaStart = position.utf8Offset
    self.contentStart = (position + token.leadingTriviaLength).utf8Offset
    self.contentEnd = (position + token.leadingTriviaLength + token.contentLength).utf8Offset
    self.triviaEnd = (position + token.totalLength).utf8Offset

    let text = token.description.utf8
    self.leadingTrivia = String(text.prefix(token.leadingTriviaLength.utf8Length))!
    self.content = String(text.dropFirst(token.leadingTriviaLength.utf8Length).dropLast(token.trailingTriviaLength.utf8Length))!
    self.trailingTrivia = String(text.suffix(token.trailingTriviaLength.utf8Length))!
  }
}

fileprivate extension TokenSyntax {
  func decomposed(at position: AbsolutePosition? = nil) -> DecomposedToken {
    return DecomposedToken(from: self, at: position ?? self.position)
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
