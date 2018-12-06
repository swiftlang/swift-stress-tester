// SwiftEvolve/Invocation.swift - Command line argument handling
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
/// This file specifies and parses the command line for swift-evolve.
///
// -----------------------------------------------------------------------------

import Foundation

struct Invocation {
  var command: String
  var seed: UInt64 = LinearCongruentialGenerator.makeSeed()
  var planFile: URL?
  var files: [URL] = []
  var replace: Bool = false
}

extension Invocation: RawRepresentable, CustomStringConvertible {
  init?(rawValue args: [String]) {
    guard let command = args.first else { return nil }

    self.command = command

    for arg in args.dropFirst() {
      if let replace = arg.parseArg(named: "replace") {
        self.replace = replace
      }
      else if let seed = arg.parseArg(named: "seed", as: UInt64.self) {
        self.seed = seed
      }
      else if let planPath = arg.parseArg(named: "plan", as: String.self) {
        self.planFile = URL(fileURLWithPath: planPath)
      }
      else if let path = arg.parseArg(named: nil, as: String.self) {
        self.files.append(URL(fileURLWithPath: path))
      }
      else {
        fatalError("Unrecognized argument \(arg)")
      }
    }
  }

  var rawValue: [String] {
    var args = [command, "--seed=\(seed)"]
    if replace {
      args.append("--replace")
    }
    if let planFile = planFile {
      args.append("--plan=\(planFile.path)")
    }
    args += files.map { $0.path }

    return args
  }

  var description: String {
    return rawValue.map { $0.shellEscaped }.joined(separator: " ")
  }
}

extension String {
  fileprivate func parseArg(named name: String) -> Bool? {
    if self == "--\(name)" {
      return true
    }
    return parseArg(named: name, as: Bool.self)
  }

  fileprivate func parseArg<T>(named name: String?, as type: T.Type) -> T?
    where T: LosslessStringConvertible
  {
    guard let name = name else {
      if hasPrefix("--") { return nil }
      return type.init(self)
    }
    guard hasPrefix("--\(name)=") else { return nil }
    return type.init(String(dropFirst(3 + name.count)))
  }

  fileprivate var shellEscaped: String {
    // FIXME This must perform horribly.
    return String(lazy.flatMap { shellSafe.contains($0) ? [$0] : ["\\", $0] })
  }
}

fileprivate let shellSafe =
  Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz01234556789_-=./")
