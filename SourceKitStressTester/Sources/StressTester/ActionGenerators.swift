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

import Foundation
import SwiftSyntax

public protocol ActionGenerator {
  func generate(for tree: SourceFileSyntax) -> [Action]
}

extension ActionGenerator {
  /// Entrypoint intended for testing purposes only
  public func generate(for file: URL) -> [Action] {
    let tree = try! SyntaxParser.parse(file)
    return generate(for: tree)
  }

  /// Entrypoint intended for testing purposes only
  public func generate(for source: String) -> [Action] {
    let tree = try! SyntaxParser.parse(source: source)
    return generate(for: tree)
  }

  fileprivate func generatePositionActions(
    for actionToken: ActionToken,
    at position: AbsolutePosition,
    withReplaceTexts: Bool
  ) -> [Action] {
    var actions = [Action]()
    let token = actionToken.token
    let (leadingTrivia, content, trailingTrivia) = token.pieces

    // insert leading trivia
    let triviaStart = position.utf8Offset
    if withReplaceTexts && token.leadingTriviaLength.utf8Length > 0 {
      actions.append(.replaceText(offset: triviaStart, length: 0, text: leadingTrivia))
      actions.append(.collectExpressionType)
    }

    // actions to perform at the content-start position prior to content insertion
    let contentStart = (position + token.leadingTriviaLength).utf8Offset
    for frontAction in actionToken.frontActions {
      switch frontAction {
      case .codeComplete:
        let expected: ExpectedResult? = withReplaceTexts ? nil : actionToken.frontExpectedResult
        actions.append(.codeComplete(offset: contentStart, expectedResult: expected))
      case .conformingMethodList:
        actions.append(.conformingMethodList(offset: contentStart))
      case .typeContextInfo:
        actions.append(.typeContextInfo(offset: contentStart))
      case .cursorInfo, .format:
        break // handled after content insertion
      }
    }

    // insert content
    if withReplaceTexts && token.contentLength.utf8Length > 0 {
      actions.append(.replaceText(offset: contentStart, length: 0, text: content))
    }

    // actions to perform at the content-start position after content insertion
    for frontAction in actionToken.frontActions {
      switch frontAction {
      case .codeComplete, .conformingMethodList, .typeContextInfo:
      break // handled before content insertion
      case .cursorInfo:
        actions.append(.cursorInfo(offset: contentStart))
      case .format:
        actions.append(.format(offset: contentStart))
      }
    }

    // actions to perform at the content-end position
    let contentEnd = (position + token.leadingTriviaLength + token.contentLength).utf8Offset
    for rearAction in actionToken.rearActions {
      switch rearAction {
      case .cursorInfo:
        actions.append(.cursorInfo(offset: contentEnd))
      case .codeComplete:
        actions.append(.codeComplete(offset: contentEnd, expectedResult: nil))
      case .conformingMethodList:
        actions.append(.conformingMethodList(offset: contentEnd))
      case .typeContextInfo:
        actions.append(.typeContextInfo(offset: contentEnd))
      case .format:
        actions.append(.format(offset: contentEnd))
      }
    }

    // insert trailing trivia
    if withReplaceTexts && token.trailingTriviaLength.utf8Length > 0 {
      actions.append(.replaceText(offset: contentEnd, length: 0, text: trailingTrivia))
    }

    return actions
  }
}

/// Walks through the provided source files token by token, generating
/// CursorInfo, RangeInfo, and CodeComplete actions as it goes.
public final class RequestActionGenerator: ActionGenerator {

  public init() {}

  public func generate(for tree: SourceFileSyntax) -> [Action] {
    let collector = ActionTokenCollector()
    let actions: [Action] = [.collectExpressionType] + collector
      .collect(from: tree)
      .flatMap(generateActions)

    // group actions that resuse a single AST together
    return actions.sorted { rank($0) < rank($1) }
  }

  private func generateActions(for actionToken: ActionToken) -> [Action] {
    let token = actionToken.token

    // position actions
    var actions = generatePositionActions(for: actionToken, at: token.position, withReplaceTexts: false)

    // range actions
    let rangeEnd = token.endPositionBeforeTrailingTrivia.utf8Offset
    actions += actionToken.endedRangeStartTokens.map { startToken in
      let rangeStart = startToken.positionAfterSkippingLeadingTrivia.utf8Offset
      assert(rangeEnd - rangeStart > 0)
      return Action.rangeInfo(offset: rangeStart, length: rangeEnd - rangeStart)
    }
    return actions
  }

  private func rank(_ action: Action) -> Int {
    switch action {
    case .replaceText:
      assertionFailure("The RequestActionGenerator produced a replaceText action")
      return 0
    case .collectExpressionType:
      return 1
    case .format:
      return 2
    case .cursorInfo:
      return 3
    case .rangeInfo:
      return 4
    case .codeComplete:
      return 5
    case .typeContextInfo:
      return 6
    case .conformingMethodList:
      return 7
    }
  }
}

/// Walks through the provided source files token by token, editing each identifier to be misspelled, and
/// unbalancing braces and brackets. Each misspelling or removed brace is restored before the next edit.
public final class TypoActionGenerator: ActionGenerator {
    public init() {}

    public func generate(for tree: SourceFileSyntax) -> [Action] {
        let collector = ActionTokenCollector()
        return collector.collect(from: tree)
            .flatMap { generateActions(for: $0) }
    }

    private func updateSpelling(_ kind: TokenKind) -> (original: String, new: String)? {
        switch kind {
        case .rightParen:
            return (")", "")
        case .rightBrace:
            return ("}", "")
        case .rightAngle:
            return (">", "")
        case .rightSquareBracket:
            return ("]", "")
        case .identifier(let spelling):
            switch spelling.prefix(1) {
            case "":
                return nil
            case "_":
                return (spelling, "x" + spelling.dropFirst())
            default:
                return (spelling, "\\." + spelling.dropFirst())
            }
        case .dollarIdentifier(let spelling):
            assert(spelling.prefix(1) == "$")
            guard let number = Int(spelling.dropFirst(1)), number < 9 else { return nil }
            return (spelling, "$\(number + 1)")
        default:
            return nil
        }
    }

    private func generateActions(for actionToken: ActionToken) -> [Action] {
        let token = actionToken.token
        guard let spelling = updateSpelling(token.tokenKind), token.presence == .present else { return [] }
        let contentStart = token.positionAfterSkippingLeadingTrivia.utf8Offset
        let contentLength = token.contentLength.utf8Length
        return [
            .replaceText(offset: contentStart, length: contentLength, text: spelling.new),
            .cursorInfo(offset: contentStart),
            .format(offset: contentStart),
            .codeComplete(offset: contentStart + spelling.new.utf8.count, expectedResult: actionToken.frontExpectedResult),
            .typeContextInfo(offset: contentStart + spelling.new.utf8.count),
            .conformingMethodList(offset: contentStart + spelling.new.utf8.count),
            .replaceText(offset: contentStart, length: spelling.new.utf8.count, text: spelling.original)
        ]
    }
}

/// Works through the provided source files generating actions to first remove their
/// content, and then add it back again token by token. CursorInfo, RangeInfo and
/// CodeComplete actions are also emitted at applicable locations.
public final class BasicRewriteActionGenerator: ActionGenerator {
  public init() {}

  public func generate(for tree: SourceFileSyntax) -> [Action] {
    let collector = ActionTokenCollector()
    let tokens = collector.collect(from: tree)
    return [.replaceText(offset: 0, length: tree.endPosition.utf8Offset, text: "")] +
      tokens.flatMap(generateActions)
  }

  private func generateActions(for actionToken: ActionToken) -> [Action] {
    // position actions
    let token = actionToken.token
    var actions = generatePositionActions(for: actionToken, at: token.position, withReplaceTexts: true)

    // range actions
    let rangeEnd = token.endPositionBeforeTrailingTrivia.utf8Offset
    actions += actionToken.endedRangeStartTokens.map { startToken in
      let rangeStart = startToken.positionAfterSkippingLeadingTrivia.utf8Offset
      assert(rangeEnd - rangeStart > 0)
      return .rangeInfo(offset: rangeStart, length: rangeEnd - rangeStart)
    }

    return actions
  }
}

public final class ConcurrentRewriteActionGenerator: ActionGenerator {
  public init() {}

  public func generate(for tree: SourceFileSyntax) -> [Action] {
    var actions: [Action] = [.replaceText(offset: 0, length: tree.totalLength.utf8Length, text: "")]
    let groups = tree.statements.map { statement -> ActionTokenGroup in
      let collector = ActionTokenCollector()
      return ActionTokenGroup(collector.collect(from: statement))
    }

    var done = false
    while !done {
      done = true
      var position = tree.position
      for group in groups {
        let nextPos = position + group.placedLength
        if let next = group.next() {
          actions += generateActions(for: next, at: nextPos, in: group, at: position, from: groups)
          done = false
        }
        position += group.placedLength
      }
    }
    return actions
  }

  private func generateActions(
    for actionToken: ActionToken,
    at position: AbsolutePosition,
    in group: ActionTokenGroup,
    at groupPos: AbsolutePosition,
    from groups: [ActionTokenGroup]
  ) -> [Action] {
    // position actions
    let token = actionToken.token
    var actions = generatePositionActions(for: actionToken, at: position, withReplaceTexts: true)

    // range actions
    let rangeEnd = (position + token.leadingTriviaLength + token.contentLength).utf8Offset
    actions += actionToken.endedRangeStartTokens.map { startToken in
      // The start token should be:
      // 1) from the same group, or
      // 2) from the very first group (if this is the last token of the last group)
      let rangeStart: Int
      if groups.first?.actionTokens.first?.token == startToken {
        rangeStart = (AbsolutePosition(utf8Offset: 0) + startToken.leadingTriviaLength).utf8Offset
      } else {
        assert(group.actionTokens.contains { $0.token == startToken })
        let placedLength: SourceLength = group.actionTokens
          .prefix { $0.token != startToken }
          .map { $0.token.totalLength }
          .reduce(.zero, +)
        rangeStart = (groupPos + placedLength + startToken.leadingTriviaLength).utf8Offset
      }
      assert(rangeEnd - rangeStart > 0)
      return .rangeInfo(offset: rangeStart, length: rangeEnd - rangeStart)
    }

    return actions
  }
}

/// Works through the given source files, first removing their content, then
/// re-introducing it token by token, from the most deeply nested token to the
/// least. Actions are emitted before and after each inserted token as it is
/// inserted.
public final class InsideOutRewriteActionGenerator: ActionGenerator {
  public init() {}

  public func generate(for tree: SourceFileSyntax) -> [Action] {
    var actions: [Action] = [.replaceText(offset: 0, length: tree.totalLength.utf8Length, text: "")]
    let collector = ActionTokenCollector()
    let actionTokens = collector.collect(from: tree)
    let depths = Set(actionTokens.map { $0.depth }).sorted(by: >)
    let groups = actionTokens
      .divide { $0.depth }
      .map { ActionTokenGroup(Array($0)) }

    for depth in depths {
      var position = tree.position
      for group in groups {
        if group.unplaced.first?.depth == depth {
          var nextPos = position + group.placedLength
          while let next = group.next() {
            actions += generateActions(for: next, at: nextPos, in: group, groups: groups)
            nextPos = position + group.placedLength
          }
        }
        position += group.placedLength
      }
    }

    // This strategy may result in duplicate, adjacent actions. Dedupe them if
    // they're non-source-mutating.
    var previous: Action? = nil
    return actions.filter { action in
      defer { previous = action }
      if case .replaceText = action { return true }
      return action != previous
    }
  }

  private func generateActions(
    for actionToken: ActionToken,
    at position: AbsolutePosition,
    in group: ActionTokenGroup,
    groups: [ActionTokenGroup]
  ) -> [Action] {
    // position actions
    let token = actionToken.token
    var actions = generatePositionActions(for: actionToken, at: position, withReplaceTexts: true)

    // range actions for ranges this token ends
    let rangeEnd = (position + token.leadingTriviaLength + token.contentLength).utf8Offset
    actions += actionToken.endedRangeStartTokens.compactMap { startToken in
      guard let startTokenStart = getPlacedStart(of: startToken, in: groups) else { return nil }
      let rangeStart = startTokenStart.utf8Offset
      assert(rangeEnd - rangeStart > 0)
      return Action.rangeInfo(offset: rangeStart, length: rangeEnd - rangeStart)
    }

    // range actions for ranges this token starts
    let rangeStart = (position + token.leadingTriviaLength).utf8Offset
    actions += actionToken.startedRangeEndTokens.compactMap { endToken in
      guard let endTokenStart = getPlacedStart(of: endToken, in: groups) else { return nil }
      let rangeEnd = (endTokenStart + endToken.contentLength).utf8Offset
      assert(rangeEnd - rangeStart > 0)
      return Action.rangeInfo(offset: rangeStart, length: rangeEnd - rangeStart)
    }

    return actions
  }

  private func getPlacedStart(of token: TokenSyntax, in groups: [ActionTokenGroup]) -> AbsolutePosition? {
    guard let groupIndex = groups.firstIndex(where: { $0.actionTokens.contains { $0.token == token } }) else {
      preconditionFailure("token is contained in provided groups")
    }
    let group = groups[groupIndex]
    let placedActionTokens = group.actionTokens[..<group.unplaced.startIndex]
    guard let index = placedActionTokens.firstIndex(where: { $0.token == token }) else {
      return nil // the token hasn't been placed yet
    }
    let totalLength: SourceLength = groups[..<groupIndex].map { $0.placedLength }.reduce(.zero, +) +
      placedActionTokens[..<index].map { $0.token.totalLength }.reduce(.zero, +) +
      token.leadingTriviaLength

    return AbsolutePosition(utf8Offset: 0) + totalLength
  }
}

private final class ActionTokenGroup {
  var actionTokens: [ActionToken]
  var unplaced: ArraySlice<ActionToken>
  var placedLength: SourceLength = .zero

  init(_ actionTokens: [ActionToken]) {
    self.actionTokens = actionTokens
    unplaced = self.actionTokens[...]
  }

  func next() -> ActionToken? {
    if let next = unplaced.popFirst() {
      placedLength += next.token.totalLength
      return next
    }
    return nil
  }
}

private enum SourcePosAction {
  case cursorInfo, codeComplete, conformingMethodList, typeContextInfo, format
}

private struct ActionToken {
  let token: TokenSyntax
  let depth: Int
  let frontActions: [SourcePosAction]
  let rearActions: [SourcePosAction]
  let endedRangeStartTokens: [TokenSyntax]
  let startedRangeEndTokens: [TokenSyntax]
  let frontExpectedResult: ExpectedResult?

  init(_ token: TokenSyntax, atDepth depth: Int, withFrontActions front: [SourcePosAction], withRearActions rear: [SourcePosAction]) {
    self.token = token
    self.depth = depth
    self.frontActions = front
    self.rearActions = rear
    self.frontExpectedResult = ActionToken.expectedResult(for: token)

    var previous: TokenSyntax? = token
    self.endedRangeStartTokens = token.tokenKind == .eof ? [] : token.ancestors
      .prefix { $0.lastToken == token }
      .compactMap { ancestor in
        defer { previous = ancestor.firstToken }
        return ancestor.firstToken == previous ? nil : ancestor.firstToken
      }
    previous = token
    self.startedRangeEndTokens = token.tokenKind == .eof ? [] : token.ancestors
      .prefix { $0.firstToken == token }
      .compactMap { ancestor in
        defer { previous = ancestor.lastToken }
        return ancestor.lastToken == previous ? nil : ancestor.lastToken
      }
  }

  /// A nil result means the results shouldn't be checked, e.g. if the provided token corresponds to the
  /// name of a newly declared variable.
  static private func expectedResult(for token: TokenSyntax) -> ExpectedResult? {
    guard token.isReference else { return nil }

    // FIXME: test dollar identifiers once code completion reports them
    if case .dollarIdentifier = token.tokenKind { return nil }

    // FIXME: completely ignore ifconfig clauses (conditions and code blocks)
    if token.ancestors.contains(where: { $0.is(IfConfigClauseListSyntax.self) }) { return nil }

    guard let parent = token.parent else { return nil }

    // Report argument label completions for any arguments other than the first
    if let tupleElem = parent.as(TupleExprElementSyntax.self), tupleElem.label == token {
      switch tupleElem.parent?.parent?.as(SyntaxEnum.self) {
      case .functionCallExpr: fallthrough
      case .subscriptExpr: fallthrough
      case .expressionSegment:
        guard tupleElem.indexInParent != 0 else { return nil }
        return ExpectedResult(name: SwiftName(base: token.textWithoutBackticks + ":", labels: []), kind: .reference)
      default:
        return nil
      }
    }
    if let parent = parent.as(IdentifierExprSyntax.self), parent.identifier == token {
      if let refArgs = parent.declNameArguments {
        let name = SwiftName(base: token.text, labels: refArgs.arguments.map{ $0.name.text })
        return ExpectedResult(name: name, kind: .reference)
      }
      if let (kind, callArgs) = getParentArgs(of: parent) {
        let name = SwiftName(base: token.text, labels: callArgs)
        return ExpectedResult(name: name, kind: kind)
      }
    }
    if let parent = parent.as(MemberAccessExprSyntax.self), parent.name == token {
      if let refArgs = parent.declNameArguments {
        let name = SwiftName(base: token.text, labels: refArgs.arguments.map{ $0.name.text })
        return ExpectedResult(name: name, kind: .reference)
      }
      if let (kind, callArgs) = getParentArgs(of: parent) {
        let name = SwiftName(base: token.text, labels: callArgs)
        return ExpectedResult(name: name, kind: kind)
      }
    }
    let name = SwiftName(base: token.text, labels: [])
    return ExpectedResult(name: name, kind: .reference)
  }

  static func getParentArgs<T:SyntaxProtocol>(of syntax: T) -> (kind: ExpectedResult.Kind, args: [String])? {
    guard let parent = syntax.parent else { return nil }
    if let call = parent.as(FunctionCallExprSyntax.self) {
      // Check for: Bar.foo(instanceOfBar)(x:1)
      if call.argumentList.count == 1 &&
         call.argumentList.allSatisfy({$0.label == nil}) {
        if let outerCall = call.parent?.as(FunctionCallExprSyntax.self),
           Syntax(outerCall.calledExpression) == parent {
          // The outer call args correspond to foo if they have any labels. If
          // they don't have labels we can't actually tell syntactically whether
          // the outer or inner argument list corresponds to foo. In that case
          // though reporting the outer argument list is the safer choice as it
          // can be empty - indicating that foo may have no paramters - while
          // the inner list always has one argument. If foo has at least one
          // parameter, the number of unlabelled arguments we report here
          // doesn't matter, so either list is fine. The logic that matches
          // the argument list reported here against the actual parameters
          // reported in the completion result assumes any parameter could be
          // defaulted or variadic, so with too few arguments the unmatched
          // params are assumed to be defaulted, and with too many arguments and
          // at least one parameter, the extras are assumed to be variadic terms
          // of the last parameter. If foo has no parameters however, there's no
          // possibly-variadic parameter to match arguments, so it will fail.
          return (.call, outerCall.argumentList.map{ $0.label?.text ?? "_" })
        }
      }
      let kind: ExpectedResult.Kind
      if call.ancestors.contains(where: { $0.is(ExpressionPatternSyntax.self) }) {
        kind = .pattern
      } else {
        kind = .call
      }
      return (kind, call.argumentList.map{ $0.label?.text ?? "_" })
    }
    return nil
  }
}

private class ActionTokenCollector: SyntaxAnyVisitor {
  var tokens = [ActionToken]()
  var currentDepth = 0

  override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
    if shouldIncreaseDepth(node) {
      currentDepth += 1
    }
    return .visitChildren
  }

  override func visitAnyPost(_ node: Syntax) {
    if shouldIncreaseDepth(node) {
      assert(currentDepth > 0)
      currentDepth -= 1
    }
  }

  override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
    _ = visitAny(Syntax(token))
    let frontActions = getFrontActions(for: token)
    let rearActions = getRearActions(for: token)
    tokens.append(ActionToken(token, atDepth: currentDepth,
                              withFrontActions: frontActions,
                              withRearActions: rearActions))
    return .visitChildren
  }

  private func getFrontActions(for token: TokenSyntax) -> [SourcePosAction] {
    if token.isIdentifier {
      return [.cursorInfo, .format, .codeComplete, .typeContextInfo, .conformingMethodList]
    }
    if !token.isOperator && token.ancestors.contains(where: {($0.isProtocol(ExprSyntaxProtocol.self) || $0.isProtocol(TypeSyntaxProtocol.self)) && $0.firstToken == token}) {
      return [.format, .codeComplete, .typeContextInfo, .conformingMethodList]
    }
    if case .contextualKeyword(let text) = token.tokenKind, ["get", "set", "didSet", "willSet"].contains(text) {
      return [.format, .codeComplete, .typeContextInfo, .conformingMethodList]
    }
    return [.format]
  }

  private func getRearActions(for token: TokenSyntax) -> [SourcePosAction] {
    if token.isIdentifier {
      return [.codeComplete, .typeContextInfo, .conformingMethodList]
    }
    if !token.isOperator && token.ancestors.contains(where: {($0.isProtocol(ExprSyntaxProtocol.self) || $0.isProtocol(TypeSyntaxProtocol.self)) && $0.lastToken == token}) {
      return [.codeComplete, .typeContextInfo, .conformingMethodList]
    }
    if case .contextualKeyword(let text) = token.tokenKind, ["get", "set", "didSet", "willSet"].contains(text) {
      return [.codeComplete, .typeContextInfo, .conformingMethodList]
    }
    return []
  }

  private func shouldIncreaseDepth(_ node: Syntax) -> Bool {
    return true
  }

  func collect<S: SyntaxProtocol>(from tree: S) -> [ActionToken] {
    tokens.removeAll()
    walk(Syntax(tree))
    return tokens
  }
}
