// SwiftEvolveKit/CodableTypeMap.swift - Explicitly typed Codables
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
/// Defines types and methods to emit instances of Codable-conforming
/// existentials with explicit type information.
///
// -----------------------------------------------------------------------------

import Foundation

/// - Warning: This is not used yet and might never be.
public struct CodableTypeDictionary {
  public init() {}

  var types: [String: Codable.Type] = [:]
  var names: [ObjectIdentifier: String] = [:]

  public subscript(_ type: Codable.Type) -> String? {
    get {
      return names[ObjectIdentifier(type)]
    }
    set {
      if let oldName = names[ObjectIdentifier(type)] {
        types[oldName] = nil
      }

      names[ObjectIdentifier(type)] = newValue

      if let newName = newValue {
        types[newName] = type
      }
    }
  }

  public subscript(_ name: String) -> Codable.Type? {
    return types[name]
  }
}

extension CodableTypeDictionary: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (Codable.Type, String)...) {
    self.init()
    for (type, name) in elements {
      self[type] = name
    }
  }
}

extension CodableTypeDictionary: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: Codable.Type...) {
    self.init()
    for type in elements {
      self[type] = String(reflecting: type)
    }
  }
}

extension CodableTypeDictionary {
  fileprivate enum CodingKeys: CodingKey {
    case type, value
  }
}

extension KeyedEncodingContainer {
  public mutating func encode<T>(
    _ value: T, forKey key: K, using typeDictionary: CodableTypeDictionary
  ) throws where T : Codable {
    guard let typeName = typeDictionary[type(of: value)] else {
      throw EncodingError.invalidValue(value, EncodingError.Context(
        codingPath: codingPath,
        debugDescription: "Type \(type(of: value)) is not present in type dictionary"
      ))
    }

    var container = nestedContainer(
      keyedBy: CodableTypeDictionary.CodingKeys.self, forKey: key
    )
    try container.encode(typeName, forKey: .type)

    let nestedEncoder = container.superEncoder(forKey: .value)
    try value.encode(to: nestedEncoder)
  }
}

extension KeyedDecodingContainer {
  public func decode<T>(
    _ type: T.Type, forKey key: K, using typeDictionary: CodableTypeDictionary
  ) throws -> T where T: Codable {
    let container = try nestedContainer(
      keyedBy: CodableTypeDictionary.CodingKeys.self, forKey: key
    )

    let name = try container.decode(String.self, forKey: .type)
    guard let type = typeDictionary[name] else {
      throw DecodingError.dataCorruptedError(
        forKey: .type, in: container,
        debugDescription: "Type named \(name) is not present in type dictionary"
      )
    }

    let decoder = try container.superDecoder(forKey: .value)
    guard let value = try type.init(from: decoder) as? T else {
      throw DecodingError.dataCorruptedError(
        forKey: .type, in: container,
        debugDescription: "Type dictionary entry \(type) is not a subtype of \(T.self)"
      )
    }
    return value
  }
}
