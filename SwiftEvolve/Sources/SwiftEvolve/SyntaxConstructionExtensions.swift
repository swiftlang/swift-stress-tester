// SwiftEvolveKit/SyntaxTriviaExtensions.swift - SwiftSyntax making extensions
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
// -----------------------------------------------------------------------------
///
/// This file includes extensions to create new SwiftSyntax nodes.
///
// -----------------------------------------------------------------------------

import SwiftSyntax

protocol TrailingCommaSyntax: SyntaxProtocol {
  func withTrailingComma(_ token: TokenSyntax?) -> Self
}

extension FunctionParameterSyntax: TrailingCommaSyntax {}
extension GenericRequirementSyntax: TrailingCommaSyntax {}

extension BidirectionalCollection where Element: TrailingCommaSyntax {
  func withCorrectTrailingCommas(betweenTrivia: Trivia = [.spaces(1)]) -> [Element] {
    var elems: [Element] = []

    for elem in dropLast() {
      let newComma = TokenSyntax.commaToken(trailingTrivia: betweenTrivia)
      let newElem = elem.withTrailingComma(newComma)
      elems.append(newElem)
    }
    if let last = last {
      elems.append(last.withTrailingComma(nil))
    }

    return elems
  }
}

extension Collection {
  func mapToFunctionParameterClause(
    outerLeadingTrivia: Trivia = [],
    innerLeadingTrivia: Trivia = [],
    betweenTrivia: Trivia = [.spaces(1)],
    innerTrailingTrivia: Trivia = [],
    outerTrailingTrivia: Trivia = [],
    _ transform: (Element) throws -> FunctionParameterSyntax
  ) rethrows -> ParameterClauseSyntax {
    let params = try map(transform)
      .withCorrectTrailingCommas(betweenTrivia: betweenTrivia)

    return ParameterClauseSyntax(
      leftParen: .leftParenToken(
        leadingTrivia: outerLeadingTrivia, trailingTrivia: innerLeadingTrivia
      ),
      parameterList: FunctionParameterListSyntax(params),
      rightParen: .rightParenToken(
        leadingTrivia: innerTrailingTrivia, trailingTrivia: outerTrailingTrivia
      )
    )
  }
  
  func mapToCodeBlock(
    outerLeadingTrivia: Trivia = [.spaces(1)],
    innerLeadingTrivia: Trivia = [.newlines(1)],
    statementLeadingTrivia: Trivia = [.spaces(2)],
    statementTrailingTrivia: Trivia = [.newlines(1)],
    innerTrailingTrivia: Trivia = [],
    outerTrailingTrivia: Trivia = [.newlines(1)],
    _ transform: (Element) throws -> CodeBlockItemSyntax.Item
  ) rethrows -> CodeBlockSyntax {
    let stmts = try map {
      CodeBlockItemSyntax(
        item: try transform($0).replacingTriviaWith(
          leading: statementLeadingTrivia, trailing: statementTrailingTrivia
        )
      )
    }
    
    return CodeBlockSyntax(
      leftBrace: .leftBraceToken(
        leadingTrivia: outerLeadingTrivia, trailingTrivia: innerLeadingTrivia
      ),
      statements: CodeBlockItemListSyntax(stmts),
      rightBrace: .rightBraceToken(
        leadingTrivia: innerTrailingTrivia, trailingTrivia: outerTrailingTrivia
      )
    )
  }
}

/// Used as a stand-in for `=` in ExprSyntaxTemplates.
infix operator ^= : AssignmentPrecedence

@dynamicMemberLookup
struct ExprSyntaxTemplate {
  static func makeExpr(
    withVars var0: String, _ var1: String,
    from template: (ExprSyntaxTemplate, ExprSyntaxTemplate) -> ExprSyntaxTemplate
  ) -> ExprSyntax {
    return template(
      ExprSyntaxTemplate(var0),
      ExprSyntaxTemplate(var1)
    ).expr
  }
  
  init(expr: ExprSyntax) {
    self.expr = expr
  }
  
  init(_ identifier: TokenSyntax) {
    guard case .identifier(_) = identifier.tokenKind else {
      preconditionFailure("ExprSyntaxTemplate(var:) called with non-identifier \(identifier)")
    }
    self.init(expr: ExprSyntax(IdentifierExprSyntax(identifier: identifier, declNameArguments: nil)))
  }
  
  init(_ name: String) {
    self.init(.identifier(name))
  }
  
  static var _self: ExprSyntaxTemplate {
    return ExprSyntaxTemplate("self")
  }
  
  private var expr: ExprSyntax
  
  static func ^= (
    lhs: ExprSyntaxTemplate, rhs: ExprSyntaxTemplate
  ) -> ExprSyntaxTemplate {
    let assignment = AssignmentExprSyntax(
      assignToken: .equalToken(
        leadingTrivia: .spaces(1), trailingTrivia: .spaces(1)
      )
    )
    let exprList = ExprListSyntax([
      lhs.expr,
      ExprSyntax(assignment),
      rhs.expr
    ])
    return ExprSyntaxTemplate(
      expr: ExprSyntax(SequenceExprSyntax(elements: exprList))
    )
  }
  
  subscript (dot identifier: TokenSyntax) -> ExprSyntaxTemplate {
    let memberAccess = MemberAccessExprSyntax(
      base: expr,
      dot: .periodToken(),
      name: identifier,
      declNameArguments: nil
    )
    return .init(expr: ExprSyntax(memberAccess))
  }
  
  subscript (dot name: String) -> ExprSyntaxTemplate {
    return self[dot: .identifier(name)]
  }
  
  subscript (dynamicMember name: String) -> ExprSyntaxTemplate {
    return self[dot: name]
  }
}
