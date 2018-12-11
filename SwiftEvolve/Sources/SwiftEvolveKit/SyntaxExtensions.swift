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

protocol DeclWithMembers: DeclSyntax {
  var members: MemberDeclBlockSyntax { get }
  func withMembers(_ newChild: MemberDeclBlockSyntax?) -> Self
}

extension ClassDeclSyntax: DeclWithMembers {}
extension StructDeclSyntax: DeclWithMembers {}
extension EnumDeclSyntax: DeclWithMembers {}
extension ProtocolDeclSyntax: DeclWithMembers {}
extension ExtensionDeclSyntax: DeclWithMembers {}

protocol DeclWithParameters: DeclSyntax {
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
      return SyntaxFactory.makeSimpleTypeIdentifier(
        name: name,
        genericArgumentClause: nil
      )
    }
    
    return SyntaxFactory.makeMemberTypeIdentifier(
      baseType: parent.typeSyntax,
      period: SyntaxFactory.makePeriodToken(),
      name: name,
      genericArgumentClause: nil
    )
  }
}

extension TypeSyntax {
  func lookup(in context: DeclContext) -> DeclContext? {
    switch self {
    case let self as SimpleTypeIdentifierSyntax:
      return context.lookupUnqualified(self.name)
      
    case let self as MemberTypeIdentifierSyntax:
      return self.baseType.lookup(in: context)?.lookupDirect(self.name)
      
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
    
    switch abs {
    case is FunctionTypeSyntax:
      return true

    case let abs as AttributedTypeSyntax:
      return abs.baseType.isFunctionType(in: dc)

    default:
      return false
    }
  }
}
