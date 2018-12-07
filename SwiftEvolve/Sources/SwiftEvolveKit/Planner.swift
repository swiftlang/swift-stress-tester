// SwiftEvolveKit/Planner.swift - Deciding how to evolve the source
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
/// This file contains the planner, which walks the syntax tree looking for
/// declarations and figures out what we want to do with them.
///
// -----------------------------------------------------------------------------

import Foundation
import SwiftSyntax

public struct PlannedEvolution: Codable {
  var sourceLocation: String
  var file: URL
  var syntaxPath: IndexPath
  var evolution: AnyEvolution
}

public class Planner<G: RandomNumberGenerator>: SyntaxVisitor {
  var rng: G
  public var plan: [PlannedEvolution] = []
  
  var url: URL!
  var context = Context()

  var potentialEvolutionsStack: [[(PlannedEvolution, Syntax)]] = []
  func addPotentialEvolution(_ evo: PlannedEvolution, on node: Syntax) {
    potentialEvolutionsStack[potentialEvolutionsStack.endIndex - 1]
      .append((evo, node))
  }

  public init(rng: G) {
    self.rng = rng
  }

  public func planEvolution(in file: SourceFileSyntax, at url: URL) {
    self.url = url.absoluteURL
    assert(context.syntaxPath.isEmpty)
    file.walk(self)
  }
  
  fileprivate func makePlannedEvolution(
    _ evolution: AnyEvolution, of node: Syntax
  ) -> PlannedEvolution {
    return PlannedEvolution(
      sourceLocation: "\(context.declContext.name) at \(node.startLocation(in: url))",
      file: url,
      syntaxPath: context.syntaxPath,
      evolution: evolution
    )
  }

  fileprivate func plan(_ node: Syntax) {
    potentialEvolutionsStack[potentialEvolutionsStack.endIndex - 1] +=
      AnyEvolution.makeAll(for: node, in: context.declContext, using: &rng)
        .map { (makePlannedEvolution($0, of: node), node) }
  }
  
  public override func visitPre(_ node: Syntax) {
    if context.enter(node) {
      potentialEvolutionsStack.append([])
    }
    plan(node)
  }
  
  public override func visitPost(_ node: Syntax) {
    let decl = context.declContext

    if context.leave(node) {
      let potentials = potentialEvolutionsStack.removeLast()

      guard let (selected, node) = potentials.randomElement(using: &rng) else {
        return
      }

      func appendWithPrerequisites(_ planned: PlannedEvolution, for node: Syntax) {
        var plannedCopy = planned
        let prereqs = planned.evolution.makePrerequisites(
          for: node, in: decl, using: &rng
        )
        for prereq in prereqs {
          plannedCopy.evolution = prereq
          appendWithPrerequisites(plannedCopy, for: node)
        }
        log("  Planning to evolve \(planned.sourceLocation) by \(planned.evolution)")
        plan.append(planned)
      }

      appendWithPrerequisites(selected, for: node)
    }
  }
}
