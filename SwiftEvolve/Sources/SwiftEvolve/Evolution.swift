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
public enum EvolutionError: Error {
  /// The evolution does not know how to handle this node. If this is a
  /// prerequisite evolution, the evolution following it cannot be performed.
  case unsupported
}

/// An Evolution is a mechanically-implementable transformation of code. Each
/// evolution knows which declarations it can be applied to; to see if it can
/// be applied to a given declaration, try to create an instance with
/// `init(for:in:using:)`.
public protocol Evolution: Codable {
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

  public func makePrerequisites<G>(
    for node: Syntax, in decl: DeclContext, using rng: inout G
  ) throws -> [Evolution] where G: RandomNumberGenerator {
    return []
  }
}

public extension AnyEvolution {
  enum Kind: String, Codable, CaseIterable {
    case shuffleMembers
    case synthesizeMemberwiseInitializer
    case shuffleGenericRequirements

    var type: Evolution.Type {
      switch self {
      case .shuffleMembers:
        return ShuffleMembersEvolution.self
      case .synthesizeMemberwiseInitializer:
        return SynthesizeMemberwiseInitializerEvolution.self
      case .shuffleGenericRequirements:
        return ShuffleGenericRequirementsEvolution.self
      }
    }
  }
}

/// An evolution which rearranges the members of a type.
public struct ShuffleMembersEvolution: Evolution {
  /// The members to be shuffled. Any indices not in this list should be moved
  /// to the end and kept in the same order.
  public var mapping: [Int]
  public var kind: AnyEvolution.Kind { return .shuffleMembers }

  public init(mapping: [Int]) {
    self.mapping = mapping
  }
}

/// An evolution which makes an implicit struct initializer explicit.
public struct SynthesizeMemberwiseInitializerEvolution: Evolution {
  struct StoredProperty: Codable, CustomStringConvertible {
    var name: String
    var type: String
    
    var description: String {
      return "\(name): \(type)"
    }
  }
  
  var inits: [[StoredProperty]]
  
  public var kind: AnyEvolution.Kind { return .synthesizeMemberwiseInitializer }
}

/// An evolution which shuffles the constraints in a generic where clause.
public struct ShuffleGenericRequirementsEvolution: Evolution {
  public var mapping: [Int]
  public var kind: AnyEvolution.Kind { return .shuffleGenericRequirements }
}

// MARK: Implementations

extension ShuffleMembersEvolution {
  public init?<G>(for node: Syntax, in decl: DeclContext, using rng: inout G) throws
    where G: RandomNumberGenerator
  {
    guard
      let membersList = node.as(MemberDeclListSyntax.self)
    else { throw EvolutionError.unsupported }
    let members = Array(membersList)

    func shouldShuffleMember(at i: Int) -> Bool {
      guard let memberDecl = members[i].decl.as(Decl.self) else {
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

  public func makePrerequisites<G>(
    for node: Syntax, in decl: DeclContext, using rng: inout G
  ) throws -> [Evolution] where G : RandomNumberGenerator {
    return [
      try SynthesizeMemberwiseInitializerEvolution
        .makeWithPrerequisites(for: node, in: decl, using: &rng)
    ].compactMap { $0 }.flatMap { $0 }
  }

  public func evolve(_ node: Syntax) -> Syntax {
    let members = Array(node.as(MemberDeclListSyntax.self)!)

    let inMapping = Set(mapping)
    let missing = members.indices.filter { !inMapping.contains($0) }
    let fullMapping = mapping + missing

    return Syntax(MemberDeclListSyntax(fullMapping.map { members[$0] }))
  }
}

extension SynthesizeMemberwiseInitializerEvolution {
  public init?<G>(for node: Syntax, in decl: DeclContext, using rng: inout G) throws
    where G : RandomNumberGenerator
  {
    guard let members = node.as(MemberDeclListSyntax.self) else {
      throw EvolutionError.unsupported
    }
    guard let lastDecl = decl.last.map(Syntax.init), lastDecl.is(StructDeclSyntax.self) else {
      return nil
    }
    guard let parent = members.parent, parent.is(MemberDeclBlockSyntax.self) else {
      return nil
    }

    var hasDefault = true
    var hasMemberwise = true
    var hasConditionalStoredProperties = false
    var properties: [StoredProperty] = []

    for membersItem in members {
      switch Syntax(membersItem.decl).as(SyntaxEnum.self) {
      case .ifConfigDecl(let ifConfig):
        if ifConfig.containsStoredMembers {
          // We would need to generate separate inits for each version. Maybe
          // someday, but not today.
          hasConditionalStoredProperties = true
        }

      case .initializerDecl(_):
        // If we declare an explicit init, we don't have implicit ones
        // FIXME: Do we need to look into IfConfigDecls for these, too? That
        // would be ludicrous.
        return nil

      case .variableDecl(let member) where member.isStored:
        // We definitely care about stored properties.
        for prop in member.boundProperties {
          if let type = prop.type {
            var typeName = type.typeText
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

      default:
        // Consistency check: This isn't somehow stored, is it?
        if let member = membersItem.decl.as(Decl.self) {
          assert(!member.isStored, "\(member.name) is a stored non-property???")
        }

        // If not, then we don't care.
        continue
      }
    }

    if hasConditionalStoredProperties {
      throw EvolutionError.unsupported
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

  public func evolve(_ node: Syntax) -> Syntax {
    let members = node.as(MemberDeclListSyntax.self)!
    
    let evolved = inits.reduce(members) { members, properties in
      let parameters = properties.mapToFunctionParameterClause {
        FunctionParameterSyntax(
          attributes: nil,
          modifiers: nil,
          firstName: .identifier($0.name),
          secondName: nil,
          colon: .colonToken(trailingTrivia: [.spaces(1)]),
          type: TypeSyntax(SimpleTypeIdentifierSyntax(name: .identifier($0.type), genericArgumentClause: nil)),
          ellipsis: nil,
          defaultArgument: nil,
          trailingComma: nil
        )
      }
      
      let body = properties.mapToCodeBlock { prop in
        let expr = ExprSyntaxTemplate.makeExpr(withVars: "self", prop.name) {
          _self, arg in _self[dot: prop.name] ^= arg
        }
        return .expr(expr)
      }

      let signature = FunctionSignatureSyntax(input: parameters)

      let newInitializer = InitializerDeclSyntax(
        attributes: nil,
        modifiers: nil,
        initKeyword: .keyword(.`init`,
          leadingTrivia: [
            .newlines(2),
            .lineComment("// Synthesized by SynthesizeMemberwiseInitializerEvolution"),
            .newlines(1)
          ],
          trailingTrivia: []
        ),
        optionalMark: nil,
        genericParameterClause: nil,
        signature: signature,
        genericWhereClause: nil,
        body: body
      )
      
      return members.appending(MemberDeclListItemSyntax(
        decl: DeclSyntax(newInitializer),
        semicolon: nil
      ))
    }
    return Syntax(evolved)
  }
}

extension ShuffleGenericRequirementsEvolution {
  public init?<G>(for node: Syntax, in decl: DeclContext, using rng: inout G) throws
    where G: RandomNumberGenerator
  {
    guard
      let requirementsList = node.as(GenericRequirementListSyntax.self)
    else { throw EvolutionError.unsupported }
    let requirements = Array(requirementsList)

    let indices = requirements.indices

    let mapping = indices.shuffled(using: &rng)

    if mapping.count <= 1 { return nil }

    self.init(mapping: mapping)
  }

  public func evolve(_ node: Syntax) -> Syntax {
    let requirements = Array(node.as(GenericRequirementListSyntax.self)!)

    precondition(requirements.count == mapping.count,
                 "ShuffleGenericRequirementsEvolution mapping does not match node it's being applied to")

    let genericRequirements = GenericRequirementListSyntax(
      mapping.map { requirements[$0] }.withCorrectTrailingCommas()
    )
    return Syntax(genericRequirements)
  }
}
