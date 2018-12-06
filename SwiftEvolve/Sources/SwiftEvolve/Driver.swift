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

class Driver {
  var invocation: Invocation
  fileprivate var parsedSourceFiles: [URL: SourceFileSyntax] = [:]

  init(invocation: Invocation) {
    self.invocation = invocation
  }
}

extension Driver {
  func plan() throws {
    guard invocation.planFile == nil else { return }

    log("Planning: \(invocation)")
    
    let planner = Planner(rng: LinearCongruentialGenerator(seed: invocation.seed))

    for file in invocation.files {
      let parsed = try parsedSource(at: file)
      planner.planEvolution(in: parsed, at: file)
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
        let tempDir = try withErrorContext(url: file, debugDescription: "url(for: .itemReplacementDirectory, ...)") {
          try FileManager.default.url(for: .itemReplacementDirectory,
                                      in: .userDomainMask,
                                      appropriateFor: file.deletingLastPathComponent(),
                                      create: true)
        }
        
        let tempFile =
          tempDir.appendingPathComponent(ProcessInfo().globallyUniqueString)
            .appendingPathExtension("swift")

        try withErrorContext(url: tempFile, debugDescription: "evolved.description.write(to: tempFile, ...)") {
          try evolved.description.write(to: tempFile, atomically: true,
                                        encoding: .utf8)
        }

        try withErrorContext(url: file, debugDescription: "replaceItemAt(file, withItemAt: tempFile, ...)") {
          _ = try FileManager.default.replaceItemAt(file, withItemAt: tempFile,
                                                    backupItemName: file.lastPathComponent + "~",
                                                    options: .withoutDeletingBackupItem)
        }
      }
      else {
        print(evolved, terminator: "")
      }
    }
  }
}

fileprivate func withErrorContext<Result>(
  url: URL, debugDescription: String, do body: () throws -> Result
) throws -> Result {
  do {
    return try body()
  }
  catch let error as NSError {
    var userInfoCopy = error.userInfo
    
    userInfoCopy[NSURLErrorKey] = url
    userInfoCopy[NSDebugDescriptionErrorKey] = debugDescription
    
    throw NSError(domain: error.domain, code: error.code, userInfo: userInfoCopy)
  }
  catch {
    assertionFailure("Non-NSError: \(error)")
    throw error
  }
}

extension Driver {
  fileprivate func parsedSource(at url: URL) throws -> SourceFileSyntax {
    let parsed = try SyntaxTreeParser.parse(url)
    parsedSourceFiles[url] = parsed
    return parsed
  }
}
