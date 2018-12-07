// SwiftEvolve/Driver.swift - swift-evolve driver
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
/// This file handles the top-level logic for swift-evolve.
///
// -----------------------------------------------------------------------------

import Foundation
import SwiftSyntax
import SwiftEvolveKit

class Driver {
  var invocation: Invocation
  fileprivate var parsedSourceFiles: [URL: SourceFileSyntax] = [:]

  init(invocation: Invocation) {
    self.invocation = invocation
  }
}

extension Driver {
  func readRules() throws -> EvolutionRules {
    guard let url = invocation.rulesFile else {
      return EvolutionRules()
    }
    let jsonData = try Data(contentsOf: url)
    return try JSONDecoder().decode(EvolutionRules.self, from: jsonData)
  }
  
  func plan() throws {
    guard invocation.planFile == nil else { return }

    log("Planning: \(invocation)")
    
    let planner = Planner(
      rng: LinearCongruentialGenerator(seed: invocation.seed),
      rules: try readRules()
    )

    for file in invocation.files {
      let parsed = try parsedSource(at: file)
      try planner.planEvolution(in: parsed, at: file)
    }

    let planFile = URL(fileURLWithPath: "evolution.plan")

    let jsonEncoder = JSONEncoder()
    if #available(macOS 10.13, *) {
      jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }
    let data = try jsonEncoder.encode(planner.plan)

    try data.write(to: planFile)

    invocation.planFile = planFile
  }

  func evolve() throws {
    log("Evolving: \(invocation)")

    guard let planFile = invocation.planFile else {
      fatalError("evolve() called without a plan")
    }

    let data = try Data(contentsOf: planFile)
    let plan = try JSONDecoder().decode([PlannedEvolution].self, from: data)

    let evolver = Evolver(plan: plan)

    for file in invocation.files {
      let parsed = try parsedSource(at: file)
      let evolved = evolver.evolve(in: parsed, at: file)

      if invocation.replace {
        let tempFile = try evolved.description.write(
          toTemporaryFileWithPathExtension: "swift", appropriateFor: file
        )

        try withErrorContext(
          url: file,
          debugDescription: "replaceItemAt(file, withItemAt: tempFile, ...)"
        ) {
          _ = try FileManager.default.replaceItemAt(
            file, withItemAt: tempFile,
            backupItemName: file.lastPathComponent + "~",
            options: .withoutDeletingBackupItem
          )
        }
      }
      else {
        print(evolved, terminator: "")
      }
    }
  }
}

extension Driver {
  fileprivate func parsedSource(at url: URL) throws -> SourceFileSyntax {
    let parsed = try SyntaxTreeParser.parse(url)
    parsedSourceFiles[url] = parsed
    return parsed
  }
}
