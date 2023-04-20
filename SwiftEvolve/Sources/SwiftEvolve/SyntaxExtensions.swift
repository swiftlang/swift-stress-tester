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

public protocol DeclWithMembers: DeclSyntaxProtocol {
  var memberBlock: MemberDeclBlockSyntax { get set }
}

extension ClassDeclSyntax: DeclWithMembers {}
extension StructDeclSyntax: DeclWithMembers {}
extension EnumDeclSyntax: DeclWithMembers {}
extension ProtocolDeclSyntax: DeclWithMembers {}
extension ExtensionDeclSyntax: DeclWithMembers {}

public protocol DeclWithParameters: DeclSyntaxProtocol {
  var baseName: String { get }
  
  var parameters: ParameterClauseSyntax { get set }
}

public protocol AbstractFunctionDecl: DeclWithParameters {
  var body: CodeBlockSyntax? { get set }
}

extension InitializerDeclSyntax: AbstractFunctionDecl {
  public var baseName: String { return "init" }

  public var parameters: ParameterClauseSyntax {
    get {
      return signature.input
    }
    set {
      self = with(\.signature, signature.with(\.input, newValue))
    }
  }
}

extension FunctionDeclSyntax: AbstractFunctionDecl {
  public var baseName: String {
    return identifier.text
  }

  public var parameters: ParameterClauseSyntax {
    get {
      return signature.input
    }
    set {
      self = with(\.signature, signature.with(\.input, newValue))
    }
  }
}

extension SubscriptDeclSyntax: DeclWithParameters {
  public var baseName: String { return "subscript" }

  public var parameters: ParameterClauseSyntax {
    get {
      return indices
    }
    set {
      self = with(\.indices, newValue)
    }
  }
}

extension DeclWithParameters {
  public var name: String {
    let parameterNames = parameters.parameterList.map { param in
      "\(param.firstName.text):"
    }
    return "\( baseName )(\( parameterNames.joined() ))"
  }
}

extension SourceLocation: CustomStringConvertible {
  public var description: String {
    let file = self.file
    let line = self.line.description
    let column = self.column.description
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
    let name = TokenSyntax.identifier(last!.name)
    let parent = removingLast()
    
    if parent.declarationChain.allSatisfy({ $0 is SourceFileSyntax }) {
      // Base case
      let typeIdentifier = SimpleTypeIdentifierSyntax(
        name: name,
        genericArgumentClause: nil
      )
      return TypeSyntax(typeIdentifier)
    }
    
    let typeIdentifer = MemberTypeIdentifierSyntax(
      baseType: parent.typeSyntax,
      period: .periodToken(),
      name: name,
      genericArgumentClause: nil
    )
    return TypeSyntax(typeIdentifer)
  }
}

extension TypeSyntax {
  func lookup(in context: DeclContext) -> DeclContext? {
    switch Syntax(self).as(SyntaxEnum.self) {
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
      return typealiasDecl.initializer.value
        .absolute(in: resolved.removingLast())
    }
    return resolved.typeSyntax
  }

  func isFunctionType(in dc: DeclContext) -> Bool {
    let abs = absolute(in: dc)

    switch Syntax(abs).as(SyntaxEnum.self) {
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
    switch self {
    case .identifier, .dollarIdentifier, .integerLiteral, .floatingLiteral, .keyword:
      return true
    default:
      return false
    }
  }
}

fileprivate class TokenTextFormatter: SyntaxVisitor {
  var previous: TokenKind?
  var text: String = ""

  init() {
    super.init(viewMode: .sourceAccurate)
  }

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
