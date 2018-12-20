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
    let tree = try! SyntaxTreeParser.parse(file)
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
      actions.append(.replaceText(range: SourceRange(of: pieces.triviaStart), text: pieces.leadingTrivia))
    }

    if token.isReference, hasBoundaryBefore {
      actions.append(.codeComplete(position: pieces.contentStart))
    }
    if withReplaceTexts {
      actions.append(.replaceText(range: SourceRange(of: pieces.contentStart), text: pieces.content))
    }

    if token.isIdentifier {
      actions.append(.cursorInfo(position: pieces.contentStart))
      if hasBoundaryAfter {
        actions.append(.codeComplete(position: pieces.contentEnd))
      }
    } else if token.isLiteralExprClose {
      actions.append(.codeComplete(position: pieces.contentEnd))
    }

    if parentsAreValid {
      var node: Syntax = token
      while let parent = node.parent, !(parent is SourceFileSyntax),
        parent.endPosition.utf8Offset == node.endPosition.utf8Offset {
          if parent.positionAfterSkippingLeadingTrivia.utf8Offset != node.positionAfterSkippingLeadingTrivia.utf8Offset {
            actions.append(.rangeInfo(range: SourceRange(of: parent, includingTrivia: false)))
          }
          node = parent
      }
    }

    if !pieces.trailingTrivia.isEmpty, withReplaceTexts {
      actions.append(.replaceText(range: SourceRange(of: pieces.contentEnd), text: pieces.trailingTrivia))
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
    tree.walk(self)
    return actions
  }

  override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
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
    actions = [.replaceText(range: SourceRange(of: tree, includingTrivia: true), text: "")]
    tree.walk(self)
    return actions
  }

  override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
    actions.append(contentsOf: generateActions(for: token, withReplaceTexts: true, parentsAreValid: true))
    return .visitChildren
  }
}

final class ConcurrentRewriteActionGenerator: ActionGenerator {
  var actions = [Action]()

  func generate(for tree: SourceFileSyntax) -> [Action] {
    // clear the file contents
    actions = [.replaceText(range: SourceRange(of: tree, includingTrivia: true), text: "")]

    var groupedTokens = tree.statements.map { (length: SourceLength.zero, remaining: TokenData(of: $0).tokens[...]) }
    var tokensRemain = true

    while tokensRemain {
      tokensRemain = false

      var position = AbsolutePosition(line: 1, column: 1, utf8Offset: 0)
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
    actions = [.replaceText(range: SourceRange(of: tree, includingTrivia: true), text: "")]

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
    let fileStart = AbsolutePosition(line: 1, column: 1, utf8Offset: 0)
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
fileprivate final class TokenData: SyntaxVisitor {
  private(set) var tokens = [TokenSyntax]()
  private(set) var depths = [TokenSyntax: Int]()
  private var depth = -1

  init(of syntax: Syntax) {
    super.init()
    syntax.walk(self)
  }

  override func visitPre(_ node: Syntax) {
    depth += 1
  }

  override func visitPost(_ node: Syntax) {
    depth -= 1
  }

  override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
    tokens.append(token)
    depths[token] = depth
    return .visitChildren
  }
}


fileprivate extension SourcePosition {
  init(of syntax: Syntax, includingTrivia: Bool = false) {
    let pos = includingTrivia ? syntax.position : syntax.positionAfterSkippingLeadingTrivia
    self.init(offset: pos.utf8Offset, line: pos.line, column: pos.column)
  }

  init(atEndOf syntax: Syntax, includingTrivia: Bool = false) {
    let pos = includingTrivia ? syntax.endPositionAfterTrailingTrivia : syntax.endPosition
    self.init(offset: pos.utf8Offset, line: pos.line, column: pos.column)
  }

  init(_ position: AbsolutePosition) {
    self.init(offset: position.utf8Offset, line: position.line, column: position.column)
  }
}

fileprivate extension SourceRange {
  init(of syntax: Syntax, includingTrivia: Bool = false) {
    let start = SourcePosition(of: syntax, includingTrivia: includingTrivia)
    let end = SourcePosition(atEndOf: syntax, includingTrivia: includingTrivia)
    let length = includingTrivia ? syntax.byteSize : syntax.byteSizeAfterTrimmingTrivia
    self.init(start: start, end: end, length: length)
  }

  init(of position: SourcePosition) {
    self.init(start: position, end: position, length: 0)
  }
}

fileprivate struct DecomposedToken {
  let triviaStart: SourcePosition
  let contentStart: SourcePosition
  let contentEnd: SourcePosition
  let triviaEnd: SourcePosition

  let leadingTrivia: String
  let content: String
  let trailingTrivia: String

  init(from token: TokenSyntax, at position: AbsolutePosition) {
    self.triviaStart = SourcePosition(position)
    self.contentStart = SourcePosition(position + token.leadingTriviaLength)
    self.contentEnd = SourcePosition(position + token.leadingTriviaLength + token.contentLength)
    self.triviaEnd = SourcePosition(position + token.totalLength)

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
