// SwiftEvolve/main.swift - swift-evolve entry point
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
/// This file contains the entry point for swift-evolve.
///
// -----------------------------------------------------------------------------

import Foundation
import SwiftEvolveKit

guard var invocation = Invocation(rawValue: CommandLine.arguments) else {
  print("""
        Usage: swift evolve [--replace] [--rules=rules.json] [--seed=number]
                            [--plan=evolution.plan] file1.swift file2.swift
        """)
  exit(2)
}

func logError(_ error: Error) {
  log(error.localizedDescription)

  let e = error as NSError
  log("Debug Description:", e.debugDescription)
  log("User Info:", e.userInfo)
  
  if let le = error as? LocalizedError {
    if let fr = le.failureReason { log("Failure Reason:", fr) }
    if let rs = le.recoverySuggestion { log("Recovery Suggestion:", rs) }
  }
  
  if let e = error as? CocoaError, let u = e.underlying {
    log("Underlying Error:")
    logError(u)
  }
}

do {
  let driver = Driver(invocation: invocation)
  try driver.plan()
  try driver.evolve()
}
catch {
  log(type(of: error))
  logError(error)
  exit(1)
}
