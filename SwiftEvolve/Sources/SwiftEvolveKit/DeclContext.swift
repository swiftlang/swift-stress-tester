// SwiftEvolveKit/Decl.swift - Logic for resilient declarations
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
/// This file specifies which declarations may be resilient and how to tell if
/// they are resilient.
///
// -----------------------------------------------------------------------------

import SwiftSyntax

struct DeclContext {
  var declarationChain: [Decl] = []

  /// Looks up `name` in the last declaration in `declarationChain`.
  ///
  /// - Note: This won't work for let (x, y) declarations; that's fine for our
  ///         use cases.
  func lookupDirect(_ name: String) -> DeclContext? {
    guard let decl = last else {
      return nil
    }
    return decl.lookupDirect(name).map(self.appending(_:))
  }
  
  func lookupDirect(_ identifier: TokenSyntax) -> DeclContext? {
    return lookupDirect(identifier.withoutTrivia().text)
  }

  /// Looks up `name` in the declarations in `declarationChain`, from last to
  /// first.
  ///
  /// - Note: This won't work for let (x, y) declarations; that's fine for our
  ///         use cases.
  func lookupUnqualified(_ name: String) -> DeclContext? {
    guard !isEmpty else { return nil }
    return lookupDirect(name) ?? removingLast().lookupUnqualified(name)
  }
  
  func lookupUnqualified(_ identifier: TokenSyntax) -> DeclContext? {
    return lookupUnqualified(identifier.withoutTrivia().text)
  }
}

extension DeclContext: CustomStringConvertible {
  var name: String {
    return declarationChain.map { $0.name }.joined(separator: ".")
  }
  
  var description: String {
    return name
  }

  var isResilient: Bool {
    // Defaults to true because a source file is resilient.
    return last?.isResilient ?? true
  }

  var isStored: Bool {
    guard let prop = last as? VariableDeclSyntax else { return false }
    return prop.isStored
  }
}

extension DeclContext {
  func `is`(at node: Syntax) -> Bool {
    return !isEmpty && last! == node
  }

  var last: Decl? {
    return declarationChain.last
  }

  var isEmpty: Bool {
    return declarationChain.isEmpty
  }

  mutating func append(_ node: Decl) {
    declarationChain.append(node)
  }

  func appending(_ node: Decl) -> DeclContext {
    var copy = self
    copy.append(node)
    return copy
  }

  mutating func removeLast() {
    declarationChain.removeLast()
  }
  
  func removingLast() -> DeclContext {
    var copy = self
    copy.removeLast()
    return copy
  }
}

enum AccessLevel: String {
  case `private`, `fileprivate`, `internal`, `public`, `open`
}

extension DeclModifierSyntax {
  var accessLevel: AccessLevel? {
    return AccessLevel(rawValue: self.name.text)
  }
}

protocol Decl: DeclSyntax {
  var name: String { get }

  var isResilient: Bool { get }
  var isStored: Bool { get }

  var modifiers: ModifierListSyntax? { get }
  
  func lookupDirect(_ name: String) -> Decl?
}

extension Decl {
  var isResilient: Bool { return true }
  var isStored: Bool { return false }

  var formalAccessLevel: AccessLevel {
    return modifiers?.lazy.compactMap { $0.accessLevel }.first ?? .internal
  }
}

extension Decl where Self: DeclWithMembers {
  func lookupDirect(_ name: String) -> Decl? {
    for item in members.members {
      guard let member = item.decl as? Decl else { continue }
      if member.name == name {
        return member
      }
    }
    return nil
  }
}

extension Decl where Self: AbstractFunctionDecl {
  func lookupDirect(_ name: String) -> Decl? {
    guard let body = self.body else { return nil }
    for item in body.statements {
      guard let decl = item.item as? Decl else { continue }
      if decl.name == name {
        return decl
      }
    }
    return nil
  }
}

extension SourceFileSyntax: Decl {
  var name: String { return "(file)" }

  var modifiers: ModifierListSyntax? { return nil }
  
  func lookupDirect(_ name: String) -> Decl? {
    for item in statements {
      guard let decl = item.item as? Decl else { continue }
      if decl.name == name {
        return decl
      }
    }
    return nil
  }
}

extension ClassDeclSyntax: Decl {
  var name: String {
    return identifier.withoutTrivia().text
  }

  var isResilient: Bool {
    return !attributes.contains(named: "_fixed_layout")
  }
}

extension StructDeclSyntax: Decl {
  var name: String {
    return identifier.withoutTrivia().text
  }

  var isResilient: Bool {
    return !attributes.contains(named: "_fixed_layout")
  }
}

extension EnumDeclSyntax: Decl {
  var name: String {
    return identifier.withoutTrivia().text
  }

  var isResilient: Bool {
    return !attributes.contains(named: "_frozen")
  }
}

extension ProtocolDeclSyntax: Decl {
  var name: String {
    return identifier.withoutTrivia().text
  }
}

extension ExtensionDeclSyntax: Decl {
  var name: String {
    return String(describing: extendedType)
  }
}

extension TypealiasDeclSyntax: Decl {
  var name: String {
    return identifier.withoutTrivia().text
  }
  
  func lookupDirect(_ name: String) -> Decl? {
    fatalError("Not implemented: \(type(of: self)).lookupDirect(_:)")
  }
}

extension AssociatedtypeDeclSyntax: Decl {
  var name: String {
    return identifier.withoutTrivia().text
  }
  
  func lookupDirect(_ name: String) -> Decl? {
    fatalError("Not implemented: \(type(of: self)).lookupDirect(_:)")
  }
}

extension FunctionDeclSyntax: Decl {}

extension InitializerDeclSyntax: Decl {}

extension SubscriptDeclSyntax: Decl {
  func lookupDirect(_ name: String) -> Decl? {
    fatalError("Not implemented: \(type(of: self)).lookupDirect(_:)")
  }
}

extension PatternSyntax {
  var boundIdentifiers: [(name: TokenSyntax, type: TypeSyntax?)] {
    switch self {
    case let self as IdentifierPatternSyntax:
      return [(self.identifier.withoutTrivia(), nil)]

    case let self as AsTypePatternSyntax:
      let subnames = self.pattern.boundIdentifiers
      if let tupleType = self.type as? TupleTypeSyntax {
        return zip(subnames.map { $0.name }, tupleType.elements.map { $0.type })
          .map { ($0.0, $0.1) }
      }
      else {
        assert(subnames.count == 1)
        return [ (subnames[0].name, self.type) ]
      }

    case let self as TuplePatternSyntax:
      return self.elements.flatMap { $0.pattern.boundIdentifiers }

    case is WildcardPatternSyntax:
      return []

    default:
      return [(SyntaxFactory.makeUnknown("<unknown>"), nil)]
    }
  }
}

extension PatternBindingSyntax {
  var boundIdentifiers: [(name: TokenSyntax, type: TypeSyntax?)] {
    return pattern.boundIdentifiers.map {
      ($0.name, typeAnnotation?.type ?? $0.type)
    }
  }
}

extension VariableDeclSyntax: Decl {
  struct BoundProperty: CustomStringConvertible, TextOutputStreamable {
    var name: TokenSyntax
    var type: TypeSyntax?
    var isInitialized: Bool
    
    init(boundIdentifier: (name: TokenSyntax, type: TypeSyntax?), isInitialized: Bool) {
      self.name = boundIdentifier.name
      self.type = boundIdentifier.type
      self.isInitialized = isInitialized
    }
    
    func write<Target>(to target: inout Target) where Target: TextOutputStream {
      name.write(to: &target)
      if let type = type {
        ": ".write(to: &target)
        type.write(to: &target)
      }
      if isInitialized {
        " = <value>".write(to: &target)
      }
    }
    
    var description: String {
      var str = ""
      write(to: &str)
      return str
    }
  }
  
  var name: String {
    let list = boundProperties
    if list.count == 1 { return String(describing: list.first!.name) }
    let nameList = list.map { String(describing: $0.name) }
    return "(\( nameList.joined(separator: ", ") ))"
  }

  var boundProperties: [BoundProperty] {
    return Array(
      bindings.lazy
        .flatMap {
          zip(
            $0.boundIdentifiers,
            repeatElement($0.initializer != nil, count: .max)
          )
        }
        .map { BoundProperty(boundIdentifier: $0.0, isInitialized: $0.1) }
    )
  }

  // FIXME: Is isResilient == true correct?

  var isStored: Bool {
    return bindings.allSatisfy { binding in
      switch binding.accessor {
      case is CodeBlockSyntax:
        // There's a computed getter.
        return false

      case let accessorBlock as AccessorBlockSyntax:
        // Check the individual accessors.
        return accessorBlock.accessors.allSatisfy { accessor in
          switch accessor.accessorKind.withoutTrivia().text {
          case "willSet", "didSet":
            // These accessors are allowed on stored properties.
            return true
          default:
            // All other accessors are assumed to make this computed.
            return false
          }
        }

      default:
        // This binding doesn't include any computed getters.
        return true
      }
    }
  }
  
  func lookupDirect(_ name: String) -> Decl? {
    return nil
  }
}

//extension EnumCaseDeclSyntax: DeclWithResilience {
//
//}

// MARK: - Helpers

extension Optional where Wrapped == AttributeListSyntax {
  func contains(named name: String) -> Bool {
    return self?.contains { $0.attributeName.text == name } ?? false
  }
}
