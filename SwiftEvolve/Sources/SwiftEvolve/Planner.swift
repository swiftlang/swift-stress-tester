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
  var syntaxPath: [Int]
  var evolution: AnyEvolution
}

public class Planner<G: RandomNumberGenerator>: SyntaxVisitor {
  var rng: G
  let rules: EvolutionRules
  
  public var plan: [PlannedEvolution] = []

  /// Make this true to include line and column numbers in
  /// PlannedEvolution.sourceLocation strings, at the cost of a significant
  /// increase in planning time.
  public var includeLineAndColumn: Bool

  var url: URL!
  var fileTree: SourceFileSyntax!
  var locationConverter: SourceLocationConverter!
  var context = Context()
  var error: Error?

  // The levels of nesting here mean:
  //   - Innermost: Contains an evolution plus its prerequisites; all of these
  //     must be applied together for any of them to be valid.
  //   - Middle: Set of alternative evolution plans; we will choose one of its
  //     elements to apply.
  //   - Outer: Stack corresponding to context.declContext; we push an empty
  //     set of alternative plans when we enter a decl, and we pop a set and
  //     choose one of the alternatives when we exit it.
  var potentialEvolutionsStack: [[[PlannedEvolution]]] = []
  func addPotentialEvolution(_ evos: [PlannedEvolution], on node: Syntax) {
    potentialEvolutionsStack[potentialEvolutionsStack.endIndex - 1]
      .append(evos)
  }

  public init(rng: G, rules: EvolutionRules, includeLineAndColumn: Bool) {
    self.rng = rng
    self.rules = rules
    self.includeLineAndColumn = includeLineAndColumn
  }

  public func planEvolution(in file: SourceFileSyntax, at url: URL) throws {
    self.url = url.absoluteURL
    self.fileTree = file
    self.locationConverter = SourceLocationConverter(file: url.path, tree: file)
    context = Context()
    error = nil

    file.walk(self)

    if let error = error {
      throw error
    }
  }

  func makeLocationString(for node: Syntax) -> String {
    precondition(node.root == self.fileTree,
      "querying for location of node of a different tree than the one we started with")
    if includeLineAndColumn {
      return "at \(node.startLocation(converter: locationConverter))"
    }
    else {
      return "in \(url.path)"
    }
  }
  
  fileprivate func makePlannedEvolution(
    _ evolution: Evolution, of node: Syntax
  ) -> PlannedEvolution {
    return PlannedEvolution(
      sourceLocation: "\(context.declContext.name) \(makeLocationString(for: node))",
      file: url,
      syntaxPath: context.syntaxPath,
      evolution: AnyEvolution(evolution)
    )
  }

  fileprivate func plan(_ node: Syntax) {
    do {
      potentialEvolutionsStack[potentialEvolutionsStack.endIndex - 1] +=
        try rules.makeAll(
          for: node, in: context.declContext, using: &rng
        ).map { $0.map { makePlannedEvolution($0, of: node) } }
    }
    catch {
      self.error = error
    }
  }
  
  public override func visitPre(_ node: Syntax) {
    guard error == nil else { return }

    if context.enter(node) {
      potentialEvolutionsStack.append([])
    }
    plan(node)
  }
  
  public override func visitPost(_ node: Syntax) {
    guard error == nil else { return }

    if context.leave(node) {
      let potentials = potentialEvolutionsStack.removeLast()

      guard let selected = potentials.randomElement(using: &rng) else {
        return
      }

      for planned in selected {
        log(type: .debug, "  Planning to evolve \(planned.sourceLocation) by \(planned.evolution)")
        plan.append(planned)
      }
    }
  }
}
