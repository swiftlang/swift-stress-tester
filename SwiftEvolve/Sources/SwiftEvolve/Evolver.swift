// SwiftEvolveKit/Evolver.swift - Applies evolutions to source
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
/// This file applies an evolution plan to source code.
///
// -----------------------------------------------------------------------------

import Foundation
import SwiftSyntax

struct Context {
  var syntaxPath = IndexPath()
  var declContext = DeclContext()

  @discardableResult
  mutating func enter(_ node: Syntax) -> Bool {
    syntaxPath.append(node.indexInParent)
    if let node = node as? Decl {
      declContext.append(node)
      return true
    }
    return false
  }

  @discardableResult
  mutating func leave(_ node: Syntax) -> Bool {
    syntaxPath.removeLast()
    if declContext.last == node {
      declContext.removeLast()
      return true
    }
    return false
  }
}

public class Evolver: SyntaxRewriter {
  var plan: [URL: [IndexPath: [PlannedEvolution]]]
  var url: URL!
  
  var context = Context()
  
  public init(plan: [PlannedEvolution]) {
    self.plan = [:]
    for evo in plan {
      self.plan[evo.file, default: [:]][evo.syntaxPath, default: []].append(evo)
    }
  }

  public func evolve(in file: SourceFileSyntax, at url: URL) -> Syntax {
    self.url = url.absoluteURL
    precondition(context.syntaxPath.isEmpty)

    // Cast makes this go through the overload with
    // visitPre()/visitAny()/visitPost().
    return visit(file as Syntax)
  }

  var recursionGuard: Syntax?
  public override func visitAny(_ node: Syntax) -> Syntax? {
    // If we're recursing, we don't want to run this again--we want to rewrite
    // our children.
    guard recursionGuard != node else {
      return nil
    }
    self.recursionGuard = node
    
    context.enter(node)
    defer { context.leave(node) }
    
    let nodePlan = plan[url, default: [:]][context.syntaxPath, default: []]

    return nodePlan.reduce(visit(node)) { node, planned in
      log(type: .debug, "  Evolving \(planned.sourceLocation) by \(planned.evolution)")
      return planned.evolution.evolve(node)
    }
  }
}
