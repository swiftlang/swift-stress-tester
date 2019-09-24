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

protocol TrailingCommaSyntax: Syntax {
  func withTrailingComma(_ token: TokenSyntax?) -> Self
}

extension FunctionParameterSyntax: TrailingCommaSyntax {}
extension GenericRequirementSyntax: TrailingCommaSyntax {}

extension BidirectionalCollection where Element: TrailingCommaSyntax {
  func withCorrectTrailingCommas(betweenTrivia: Trivia = [.spaces(1)]) -> [Element] {
    var elems: [Element] = []

    for elem in dropLast() {
      let newComma = SyntaxFactory.makeCommaToken(trailingTrivia: betweenTrivia)
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
        as! [FunctionParameterSyntax]

    return SyntaxFactory.makeParameterClause(
      leftParen: SyntaxFactory.makeLeftParenToken(
        leadingTrivia: outerLeadingTrivia, trailingTrivia: innerLeadingTrivia
      ),
      parameterList: SyntaxFactory.makeFunctionParameterList(params),
      rightParen: SyntaxFactory.makeRightParenToken(
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
    _ transform: (Element) throws -> Syntax
  ) rethrows -> CodeBlockSyntax {
    let stmts = try map {
      SyntaxFactory.makeCodeBlockItem(
        item: try transform($0).replacingTriviaWith(
          leading: statementLeadingTrivia, trailing: statementTrailingTrivia
        ),
        semicolon: nil,
        errorTokens: nil
      )
    }
    
    return SyntaxFactory.makeCodeBlock(
      leftBrace: SyntaxFactory.makeLeftBraceToken(
        leadingTrivia: outerLeadingTrivia, trailingTrivia: innerLeadingTrivia
      ),
      statements: SyntaxFactory.makeCodeBlockItemList(stmts),
      rightBrace: SyntaxFactory.makeRightBraceToken(
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
    self.init(expr: SyntaxFactory.makeIdentifierExpr(identifier: identifier, declNameArguments: nil))
  }
  
  init(_ name: String) {
    self.init(SyntaxFactory.makeIdentifier(name))
  }
  
  static var _self: ExprSyntaxTemplate {
    return ExprSyntaxTemplate("self")
  }
  
  private var expr: ExprSyntax
  
  static func ^= (
    lhs: ExprSyntaxTemplate, rhs: ExprSyntaxTemplate
  ) -> ExprSyntaxTemplate {
    return ExprSyntaxTemplate(
      expr: SyntaxFactory.makeSequenceExpr(
        elements: SyntaxFactory.makeExprList([
          lhs.expr,
          SyntaxFactory.makeAssignmentExpr(
            assignToken: SyntaxFactory.makeEqualToken(
              leadingTrivia: .spaces(1), trailingTrivia: .spaces(1)
            )
          ),
          rhs.expr
          ])
      )
    )
  }
  
  subscript (dot identifier: TokenSyntax) -> ExprSyntaxTemplate {
    return .init(expr:
      SyntaxFactory.makeMemberAccessExpr(
        base: expr,
        dot: SyntaxFactory.makePeriodToken(),
        name: identifier,
        declNameArguments: nil
      )
    )
  }
  
  subscript (dot name: String) -> ExprSyntaxTemplate {
    return self[dot: SyntaxFactory.makeIdentifier(name)]
  }
  
  subscript (dynamicMember name: String) -> ExprSyntaxTemplate {
    return self[dot: name]
  }
}
