// SwiftEvolveKit/EvolutionRules.swift - Exclude certain evolutions
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
/// This file contains the type which stores information about which
/// evolutions we are permitted to perform during this run and implements
/// these rules.
///
// -----------------------------------------------------------------------------

import SwiftSyntax

public struct EvolutionRules {
  public var exclusions: [AnyEvolution.Kind: Set<String>?]

  public init(exclusions: [AnyEvolution.Kind: Set<String>?]) {
    self.exclusions = exclusions
  }

  func makeAll<G>(
    for node: Syntax, in decl: DeclContext, using rng: inout G
  ) throws -> [[Evolution]] where G: RandomNumberGenerator {
    return try allKinds(for: decl).compactMap { kind -> [Evolution]? in
      do {
        return try kind.type.makeWithPrerequisites(
          for: node, in: decl, using: &rng
        )
      }
      catch EvolutionError.unsupported {
        return nil
      }
    }
  }
  
  func allKinds(for decl: DeclContext) -> [AnyEvolution.Kind] {
    let declName = decl.name

    return AnyEvolution.Kind.allCases.filter { kind in
      permit(kind, forDeclName: declName)
    }
  }
  
  public func permit(_ kind: AnyEvolution.Kind, forDeclName declName: String) -> Bool {
    guard let excludedDeclNames = exclusions[kind, default: []] else {
      // If exclusions[kind] == Optional.some(.none), all decl names are
      // excluded.
      return false
    }
    return !excludedDeclNames.contains(declName)
  }
}

extension EvolutionRules: Decodable {
  public init() {
    self.init(exclusions: [:])
  }
  
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AnyEvolution.Kind.self)
    
    exclusions = [:]
    for key in container.allKeys {
      exclusions[key] = try container.decode(Set<String>?.self, forKey: key)
    }
  }
}

extension AnyEvolution.Kind: CodingKey, CustomStringConvertible {
  public var description: String {
    return stringValue
  }
}
