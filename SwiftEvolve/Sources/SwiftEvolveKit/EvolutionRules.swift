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
/// This file specifies and implements many ABI-compatible mechanical
/// transformations we can perform on various resilient declarations.
///
// -----------------------------------------------------------------------------

import Foundation

public struct EvolutionRules {
  var exclusions: [AnyEvolution.Kind: [String]?]
  
  func allKinds(for decl: DeclContext) -> [AnyEvolution.Kind] {
    let declName = decl.name

    return AnyEvolution.Kind.allCases.filter { kind in
      permit(kind, forDeclName: declName)
    }
  }
  
  func permit(_ kind: AnyEvolution.Kind, forDeclName declName: String) -> Bool {
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
      exclusions[key] = try container.decode([String]?.self, forKey: key)
    }
  }
}

extension AnyEvolution.Kind: CodingKey, CustomStringConvertible {
  var description: String {
    return stringValue
  }
}
