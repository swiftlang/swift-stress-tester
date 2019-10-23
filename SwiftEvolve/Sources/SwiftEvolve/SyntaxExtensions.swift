// SwiftEvolveKit/SyntaxExtensions.swift - Miscellaneous SwiftSyntax extensions
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
/// This file includes various convenience methods and abstractions used
/// in other files to work with the SwiftSyntax tree.
///
// -----------------------------------------------------------------------------

import SwiftSyntax
import Foundation

protocol DeclWithMembers: DeclSyntaxProtocol {
  var members: MemberDeclBlockSyntax { get }
  func withMembers(_ newChild: MemberDeclBlockSyntax?) -> Self
}

extension ClassDeclSyntax: DeclWithMembers {}
extension StructDeclSyntax: DeclWithMembers {}
extension EnumDeclSyntax: DeclWithMembers {}
extension ProtocolDeclSyntax: DeclWithMembers {}
extension ExtensionDeclSyntax: DeclWithMembers {}

protocol DeclWithParameters: DeclSyntaxProtocol {
  var baseName: String { get }
  
  var parameters: ParameterClauseSyntax { get }
  func withParameters(_ parameters: ParameterClauseSyntax?) -> Self
}

protocol AbstractFunctionDecl: DeclWithParameters {
  var body: CodeBlockSyntax? { get }
  func withBody(_ body: CodeBlockSyntax?) -> Self
}

extension InitializerDeclSyntax: AbstractFunctionDecl {
  var baseName: String { return "init" }
}

extension FunctionDeclSyntax: AbstractFunctionDecl {
  var baseName: String {
    return identifier.text
  }

  var parameters: ParameterClauseSyntax {
    return signature.input
  }

  func withParameters(_ parameters: ParameterClauseSyntax?) -> FunctionDeclSyntax {
    return withSignature(signature.withInput(parameters))
  }
}

extension SubscriptDeclSyntax: DeclWithParameters {
  var baseName: String { return "subscript" }

  var parameters: ParameterClauseSyntax {
    return indices
  }

  func withParameters(_ parameters: ParameterClauseSyntax?) -> SubscriptDeclSyntax {
    return withIndices(parameters)
  }
}

extension DeclWithParameters {
  var name: String {
    let parameterNames = parameters.parameterList.map { param in
      "\(param.firstName?.text ?? "_"):"
    }
    return "\( baseName )(\( parameterNames.joined() ))"
  }
}

extension SourceLocation: CustomStringConvertible {
  public var description: String {
    return "\(file):\(line):\(column)"
  }
}

func == (lhs: Syntax?, rhs: Syntax?) -> Bool {
  switch (lhs, rhs) {
  case (nil, nil):
    return true
  case (nil, _?), (_?, nil):
    return false
  case (let lhs?, let rhs?):
    return lhs == rhs
  }
}

func != (lhs: Syntax?, rhs: Syntax?) -> Bool {
  return !(lhs == rhs)
}

extension DeclContext {
  var typeSyntax: TypeSyntax {
    let name = SyntaxFactory.makeIdentifier(last!.name)
    let parent = removingLast()
    
    if parent.declarationChain.allSatisfy({ $0 is SourceFileSyntax }) {
      // Base case
      let typeIdentifier = SyntaxFactory.makeSimpleTypeIdentifier(
        name: name,
        genericArgumentClause: nil
      )
      return TypeSyntax(typeIdentifier)
    }
    
    let typeIdentifer = SyntaxFactory.makeMemberTypeIdentifier(
      baseType: parent.typeSyntax,
      period: SyntaxFactory.makePeriodToken(),
      name: name,
      genericArgumentClause: nil
    )
    return TypeSyntax(typeIdentifer)
  }
}

extension TypeSyntax {
  func lookup(in context: DeclContext) -> DeclContext? {
    switch Syntax(self).asSyntaxEnum {
    case .simpleTypeIdentifier(let simpleTypeIdentifier):
      return context.lookupUnqualified(simpleTypeIdentifier.name)
    case .memberTypeIdentifier(let memberTypeIdentifier):
      return memberTypeIdentifier.baseType.lookup(in: context)?.lookupDirect(memberTypeIdentifier.name)
    default:
      return nil
    }
  }
  
  func absolute(in dc: DeclContext) -> TypeSyntax {
    guard let resolved = lookup(in: dc) else {
      return self
    }
    if let typealiasDecl = resolved.last as? TypealiasDeclSyntax {
      return typealiasDecl.initializer!.value
        .absolute(in: resolved.removingLast())
    }
    return resolved.typeSyntax
  }

  func isFunctionType(in dc: DeclContext) -> Bool {
    let abs = absolute(in: dc)

    switch Syntax(abs).asSyntaxEnum {
    case .functionType(_):
      return true

    case .attributedType(let attributedType):
      return attributedType.baseType.isFunctionType(in: dc)

    default:
      return false
    }
  }
}

extension TypeSyntax {
  var typeText: String {
    let formatter = TokenTextFormatter()
    formatter.walk(self)
    return formatter.text
  }
}

extension TokenKind {
  var needsSpace: Bool {
    if isKeyword { return true }
    switch self {
    case .identifier, .dollarIdentifier, .integerLiteral, .floatingLiteral, .yield:
      return true
    default:
      return false
    }
  }
}

fileprivate class TokenTextFormatter: SyntaxVisitor {
  var previous: TokenKind?
  var text: String = ""

  override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
    switch token.tokenKind {
    case .comma:
      text += ", "
    case .colon:
      text += ": "
    case .arrow:
      text += " -> "
    case _ where token.tokenKind.needsSpace && (previous?.needsSpace ?? false):
      text += " " + token.text
    case _:
      text += token.text
    }
    previous = token.tokenKind
    return .skipChildren
  }
}

extension SyntaxCollection {
  var first: Element? {
    return self.first(where:{_ in true})
  }
}
