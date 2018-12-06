// SwiftEvolve/AnyEvolution.swift - Boxing evolutions
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
/// This file contains a box around Evolution existentials which can generate
/// instances of any known conforming type and serialize them with type
/// information.
///
// -----------------------------------------------------------------------------

import SwiftSyntax

struct AnyEvolution {
  var value: Evolution

  init(_ value: Evolution) {
    self.value = value
  }
}

extension AnyEvolution {
  static func makeAll<G>(for node: Syntax, in decl: DeclContext, using rng: inout G)
    -> [AnyEvolution] where G: RandomNumberGenerator
  {
    return [Kind.shuffleMembers].compactMap {
      $0.type.init(for: node, in: decl, using: &rng)
    }.map(AnyEvolution.init(_:))
  }

  static func random<G>(for node: Syntax, in decl: DeclContext, using rng: inout G)
    -> AnyEvolution? where G: RandomNumberGenerator
  {
    return makeAll(for: node, in: decl, using: &rng).randomElement(using: &rng)
  }

  func makePrerequisites<G>(for node: Syntax, in decl: DeclContext, using rng: inout G)
    -> [AnyEvolution] where G: RandomNumberGenerator {
    return value.makePrerequisites(for: node, in: decl, using: &rng)
  }

  func evolve(_ node: Syntax) -> Syntax {
    return value.evolve(node).prependingComment("Evolved: \(value)")
  }
}

extension AnyEvolution: CustomStringConvertible {
  var description: String {
    return String(describing: value)
  }
}

// MARK: Codable support

extension AnyEvolution: Codable {
  private enum CodingKeys: String, CodingKey {
    case kind
    case value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    let kind = try container.decode(Kind.self, forKey: .kind)
    let innerDecoder = try container.superDecoder(forKey: .value)
    value = try kind.type.init(from: innerDecoder)

  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    try container.encode(value.kind, forKey: .kind)
    let innerEncoder = container.superEncoder(forKey: .value)
    try value.encode(to: innerEncoder)
  }
}
