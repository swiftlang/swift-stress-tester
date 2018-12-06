// SwiftEvolve/LinearCongruentialGenerator.swift - Repeatable random number generator
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
/// This file implements a seedable random number generator that can be used to
/// reproduce previous runs of the tool.
///
// -----------------------------------------------------------------------------

// Copied from StdlibUnittest/StdlibCoreExtras.swift
@_fixed_layout
public struct LinearCongruentialGenerator: RandomNumberGenerator {

  @usableFromInline
  internal var _state: UInt64

  @inlinable
  public init(seed: UInt64) {
    _state = seed
    for _ in 0 ..< 10 { _ = next() }
  }

  @inlinable
  public mutating func next() -> UInt64 {
    _state = 2862933555777941757 &* _state &+ 3037000493
    return _state
  }
}

extension LinearCongruentialGenerator {
  static func makeSeed<G>(using rng: inout G) -> UInt64
    where G: RandomNumberGenerator
  {
    return UInt64.random(in: 0...(.max), using: &rng)
  }

  static func makeSeed() -> UInt64 {
    var systemRNG = SystemRandomNumberGenerator()
    return makeSeed(using: &systemRNG)
  }
}
