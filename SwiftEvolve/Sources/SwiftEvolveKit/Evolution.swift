// SwiftEvolveKit/Evolution.swift - Rules for mechanically evolving declarations
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
/// This file specifies and implements many ABI-compatible mechanical
/// transformations we can perform on various resilient declarations.
///
// -----------------------------------------------------------------------------

import SwiftSyntax

/// Errors with recognized meaning for evolution initialization.
enum EvolutionError: Error {
  /// The evolution does not know how to handle this node. If this is a
  /// prerequisite evolution, the evolution following it cannot be performed.
  case unsupported
}

/// An Evolution is a mechanically-implementable transformation of code. Each
/// evolution knows which declarations it can be applied to; to see if it can
/// be applied to a given declaration, try to create an instance with
/// `init(for:in:using:)`.
protocol Evolution: Codable {
  /// Attempts to create a random instance of the given evolution on `node`.
  ///
  /// - Parameter node: The syntax node we're looking to evolve.
  /// - Parameter decl: The declaration the syntax node is in.
  /// - Parameter rng: A random number generator the evolution can use to
  ///             make decisions pseudo-randomly.
  /// - Throws: Usually an `EvolutionError.unsupported` if the evolution
  ///           cannot be safely applied to `node`. Other errors can also be
  ///           thrown and will pass through all the initialization machinery.
  /// - Returns: The evolution instance, or `nil` if applying the evolution
  ///            would be a no-op.
  init?<G>(for node: Syntax, in decl: DeclContext, using rng: inout G) throws
    where G: RandomNumberGenerator

  /// Creates instances of any evolutions that need to be applied to `node`
  /// before `self` is applied.
  ///
  /// - Parameter node: The syntax node we're looking to evolve.
  /// - Parameter decl: The declaration the syntax node is in.
  /// - Parameter rng: A random number generator the evolution can use to
  ///             make decisions pseudo-randomly.
  /// - Throws: Usually an `EvolutionError.unsupported` if the evolution
  ///           cannot be safely applied to `node`.
  /// - Returns: An array of evolutions which should be applied before `self`.
  ///
  /// - Note: Implementations should usually make the prerequisite evolutions
  ///         by calling `makeWithPrerequisites(for:in:using:)`.
  func makePrerequisites<G>(
    for node: Syntax, in decl: DeclContext, using rng: inout G
  ) throws -> [Evolution] where G: RandomNumberGenerator

  /// Applies the evolution to `node`.
  ///
  /// - Parameter node: The node to evolve.
  /// - Returns: An evolved version of `decl`.
  /// - Precondition: `decl` represents the same code passed to
  ///                 `init(decl:using:)`.
  func evolve(_ node: Syntax) -> Syntax

  var kind: AnyEvolution.Kind { get }
}

extension Evolution {
  /// Creates an array containing an instance of the evolution and all
  /// evolutions that need to be applied along with it.
  ///
  /// - Parameter node: The syntax node we're looking to evolve.
  /// - Parameter decl: The declaration the syntax node is in.
  /// - Parameter rng: A random number generator the evolution can use to
  ///             make decisions pseudo-randomly.
  /// - Throws: Usually an `EvolutionError.unsupported` if the evolution
  ///           cannot be safely applied to `node`.
  /// - Returns: An array of evolutions which all need to be applied together,
  ///            or `nil` if the evolution would be a no-op.
  static func makeWithPrerequisites<G>(
    for node: Syntax, in decl: DeclContext, using rng: inout G
  ) throws -> [Evolution]? where G: RandomNumberGenerator {
    guard let evo = try self.init(for: node, in: decl, using: &rng) else {
      return nil
    }
    let prereqs = try evo.makePrerequisites(for: node, in: decl, using: &rng)
    return prereqs + [evo]
  }

  func makePrerequisites<G>(
    for node: Syntax, in decl: DeclContext, using rng: inout G
  ) throws -> [Evolution] where G: RandomNumberGenerator {
    return []
  }
}

extension AnyEvolution {
  enum Kind: String, Codable, CaseIterable {
    case shuffleMembers
    case synthesizeMemberwiseInitializer
    case changeDefaultArgument

    var type: Evolution.Type {
      switch self {
      case .shuffleMembers:
        return ShuffleMembersEvolution.self
      case .synthesizeMemberwiseInitializer:
        return SynthesizeMemberwiseInitializerEvolution.self
      case .changeDefaultArgument:
        return ChangeDefaultArgumentEvolution.self
      }
    }
  }
}

/// An evolution which rearranges the members of a type.
struct ShuffleMembersEvolution: Evolution {
  /// The members to be shuffled. Any indices not in this list should be moved
  /// to the end and kept in the same order.
  var mapping: [Int]
  var kind: AnyEvolution.Kind { return .shuffleMembers }
}

/// An evolution which makes an implicit struct initializer explicit.
struct SynthesizeMemberwiseInitializerEvolution: Evolution {
  struct StoredProperty: Codable, CustomStringConvertible {
    var name: String
    var type: String
    
    var description: String {
      return "\(name): \(type)"
    }
  }
  
  var inits: [[StoredProperty]]
  
  var kind: AnyEvolution.Kind { return .synthesizeMemberwiseInitializer }
}

/// An evolution which adds, removes, or changes a default argument.
struct ChangeDefaultArgumentEvolution: Evolution {
  var parameterIndex: Int
  var kind: AnyEvolution.Kind { return .changeDefaultArgument }
}

// MARK: Implementations

extension ShuffleMembersEvolution {
  init?<G>(for node: Syntax, in decl: DeclContext, using rng: inout G) throws
    where G: RandomNumberGenerator
  {
    guard
      let members = node as? MemberDeclListSyntax
    else { throw EvolutionError.unsupported }

    func shouldShuffleMember(at i: Int) -> Bool {
      guard let memberDecl = members[i].decl as? Decl else {
        // Don't know what this is, so conservatively leave it alone.
        return false
      }
      return decl.isResilient || !decl.appending(memberDecl).isStored
    }
    let indicesByShuffling: [Bool: [Int]] =
      Dictionary(grouping: members.indices, by: shouldShuffleMember(at:))

    let mapping = indicesByShuffling[true, default: []].shuffled(using: &rng)

    if mapping.count <= 1 { return nil }

    self.init(mapping: mapping)
  }

  func makePrerequisites<G>(
    for node: Syntax, in decl: DeclContext, using rng: inout G
  ) throws -> [Evolution] where G : RandomNumberGenerator {
    return try SynthesizeMemberwiseInitializerEvolution
      .makeWithPrerequisites(for: node, in: decl, using: &rng) ?? []
  }

  func evolve(_ node: Syntax) -> Syntax {
    let members = node as! MemberDeclListSyntax

    let inMapping = Set(mapping)
    let missing = members.indices.filter { !inMapping.contains($0) }
    let fullMapping = mapping + missing

    return SyntaxFactory.makeMemberDeclList(fullMapping.map { members[$0] })
  }
}

extension SynthesizeMemberwiseInitializerEvolution {
  init?<G>(for node: Syntax, in decl: DeclContext, using rng: inout G) throws
    where G : RandomNumberGenerator
  {
    guard let members = node as? MemberDeclListSyntax else {
      throw EvolutionError.unsupported
    }
    guard decl.last is StructDeclSyntax else {
      return nil
    }

    var hasDefault = true
    var hasMemberwise = true
    var properties: [StoredProperty] = []

    for membersItem in members {
      guard let member = membersItem.decl as? Decl else { continue }

      if member is InitializerDeclSyntax {
        // If we declare an explicit init, we don't have implicit ones
        return nil
      }
      else if member.isStored {
        guard let member = member as? VariableDeclSyntax else {
          preconditionFailure("Only variable decls should be stored")
        }
        
        for prop in member.boundProperties {
          if let type = prop.type {
            var typeName = String(describing: type)
            if type.isFunctionType(in: decl) {
              typeName = "@escaping \(typeName)"
            }
            
            properties.append(StoredProperty(
              name: prop.name.text,
              type: typeName
            ))
          } else {
            hasMemberwise = false
          }

          if !prop.isInitialized {
            hasDefault = false
          }
        }
      }
    }
    
    var inits: [[StoredProperty]] = []
    if hasDefault {
      inits.append([])
    }
    if hasMemberwise && !properties.isEmpty {
      inits.append(properties)
    }
    
    if inits.isEmpty {
      return nil
    }

    self.init(inits: inits)
  }

  func evolve(_ node: Syntax) -> Syntax {
    let members = node as! MemberDeclListSyntax
    
    return inits.reduce(members) { members, properties in
      let parameters = properties.mapToFunctionParameterClause {
        SyntaxFactory.makeFunctionParameter(
          attributes: nil,
          firstName: SyntaxFactory.makeIdentifier($0.name),
          secondName: nil,
          colon: SyntaxFactory.makeColonToken(trailingTrivia: [.spaces(1)]),
          type: SyntaxFactory.makeTypeIdentifier($0.type),
          ellipsis: nil,
          defaultArgument: nil,
          trailingComma: nil
        )
      }
      
      let body = properties.mapToCodeBlock { prop in
        ExprSyntaxTemplate.makeExpr(withVars: "self", prop.name) {
          _self, arg in _self[dot: prop.name] ^= arg
        }
      }
      
      let newInitializer = SyntaxFactory.makeInitializerDecl(
        attributes: nil,
        modifiers: nil,
        initKeyword: SyntaxFactory.makeInitKeyword(
          leadingTrivia: [
            .newlines(2),
            .lineComment("// Synthesized by SynthesizeMemberwiseInitializerEvolution"),
            .newlines(1)
          ],
          trailingTrivia: []
        ),
        optionalMark: nil,
        genericParameterClause: nil,
        parameters: parameters,
        throwsOrRethrowsKeyword: nil,
        genericWhereClause: nil,
        body: body
      )
      
      return members.appending(MemberDeclListItemSyntax {
        $0.useDecl(newInitializer)
      })
    }
  }
}

extension ChangeDefaultArgumentEvolution {
  init?<G>(for node: Syntax, in decl: DeclContext, using rng: inout G) throws
    where G: RandomNumberGenerator
  {
    guard
      let declWithParams = node as? DeclWithParameters,

      // Protocols don't support default args
      !(decl.declarationChain.dropLast().last is ProtocolDeclSyntax),

      let index = declWithParams.parameters.parameterList
                    .interestingForDefaultArguments.indices
                      .randomElement(using: &rng)
    else { throw EvolutionError.unsupported }

    self.init(parameterIndex: index)
  }

  func evolve(_ decl: Syntax) -> Syntax {
    let decl = decl as! DeclWithParameters

    return decl.withParameters(
      ParameterClauseSyntax { newParams in
        newParams.useLeftParen(decl.parameters.leftParen)

        for (i, oldParam) in zip(decl.parameters.parameterList.indices, decl.parameters.parameterList) {
          if i != parameterIndex {
            newParams.addFunctionParameter(oldParam)
            continue
          }

          let newDefaultArg: InitializerClauseSyntax?

          if let newDefaultValue = oldParam.type?.makeDefaultArgument() {
            newDefaultArg = InitializerClauseSyntax {
              $0.useEqual(SyntaxFactory.makeEqualToken())
              $0.useValue(newDefaultValue)
            }
          }
          else {
            newDefaultArg = nil
          }

          let newParam = oldParam.withDefaultArgument(newDefaultArg)
          newParams.addFunctionParameter(newParam)
        }

        newParams.useRightParen(decl.parameters.rightParen)
      }
    )
  }
}

// MARK: - Helpers

fileprivate func ~= (name: String, type: TypeSyntax) -> Bool {
  switch type {
  case is ArrayTypeSyntax:
    return "Array".contains(name)

  case is DictionaryTypeSyntax:
    return "Dictionary".contains(name)

  case is OptionalTypeSyntax:
    return "Optional".contains(name)

  case is ImplicitlyUnwrappedOptionalTypeSyntax:
    return "Optional".contains(name)

  case is MetatypeTypeSyntax:
    return "Type".contains(name)

  case let t as SimpleTypeIdentifierSyntax:
    return t.name.text.contains(name)

  case let t as MemberTypeIdentifierSyntax:
    return t.name.text.contains(name)

  case let t as CompositionTypeSyntax:
    return t.elements.contains { name ~= $0.type }

  default:
    return false
  }
}

extension TypeSyntax {
  fileprivate func makeDefaultArgument() -> ExprSyntax? {
    switch self {
    case "Array", "Set":
      return ArrayExprSyntax({ _ in })
    case "Dictionary":
      return DictionaryExprSyntax({ _ in })
    case "String", "Substring":
      return SyntaxFactory.makeStringLiteralExpr("fnord")
    case "Int":
      return SyntaxFactory.makeIntegerLiteralExpr(digits:
        SyntaxFactory.makeIntegerLiteral("42"))
    case "Double", "Float":
      return SyntaxFactory.makeFloatLiteralExpr(floatingDigits:
        SyntaxFactory.makeFloatingLiteral("42.424242"))
    case "Optional":
      return SyntaxFactory.makeBlankNilLiteralExpr()
    default:
      return nil
    }
  }
}

extension FunctionParameterListSyntax {
  var interestingForDefaultArguments:
      LazyFilterCollection<FunctionParameterListSyntax> {
    return lazy.filter {
      $0.defaultArgument != nil || $0.type?.makeDefaultArgument() != nil
    }
  }
}
