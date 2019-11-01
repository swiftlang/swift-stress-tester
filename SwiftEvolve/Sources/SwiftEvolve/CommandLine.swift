// SwiftEvolve/CommandLine.swift - Command line argument handling
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

import TSCUtility
import TSCBasic

// MARK: Argument parsing

enum CommandLineError: Error, CustomStringConvertible {
  case mutuallyExclusiveArguments(String, String)
  
  var description: String {
    switch self {
    case .mutuallyExclusiveArguments(let a, let b):
      return "cannot specify both \(a) and \(b); they are mutually exclusive"
    }
  }
}

extension SwiftEvolveTool.Step {
  public init(arguments: [String]) throws {
    let command = arguments.first!
    let rest = Array(arguments.dropFirst())
    
    let schema = ArgumentSchema()
    let result = try schema.parser.parse(rest)

    let options = Options(command: command, schema: schema, result: result)
    options.setMinimumLogTypeToPrint()

    try self.init(
      seed: result.get(schema.seed),
      planFile: result.get(schema.planFile),
      options: options
    )
  }
  
  fileprivate init(seed: UInt64?, planFile: PathArgument?, options: Options) throws {
    switch (seed, planFile) {
    case (nil, nil):
      self = .seed(options: options)
    case (let seed?, nil):
      self = .plan(seed: seed, options: options)
    case (nil, let planFile?):
      self = .evolve(planFile: planFile.path, options: options)
    case (_?, _?):
      throw CommandLineError.mutuallyExclusiveArguments("--seed", "--plan")
    }
  }
  
  fileprivate struct ArgumentSchema {
    let parser: ArgumentParser
    let usage = "[--seed=1234|--plan=plan.json] [--rules=rules.json] [--replace] file1.swift file2.swift..."
    let overview = "Automatically evolve Swift libraries"
    
    let rulesFile: OptionArgument<PathArgument>
    let seed: OptionArgument<UInt64>
    let planFile: OptionArgument<PathArgument>
    let replace: OptionArgument<Bool>
    let verbose: OptionArgument<Bool>
    let files: PositionalArgument<[PathArgument]>
    
    init() {
      parser = ArgumentParser(usage: usage, overview: overview)
      rulesFile = parser.add(option: "--rules", kind: PathArgument.self,
                             usage: "<PATH> JSON specification of plan generation rules")
      seed = parser.add(option: "--seed", kind: UInt64.self,
                        usage: "<NUM> Numeric seed for generating a plan")
      planFile = parser.add(option: "--plan", kind: PathArgument.self,
                            usage: "<PATH> JSON file specifying a pre-generated plan")
      replace = parser.add(option: "--replace", kind: Bool.self,
                           usage: "Replace files with modified versions instead of printing them")
      verbose = parser.add(option: "--verbose", shortName: "-v", kind: Bool.self,
                           usage: "Print detailed progress and make source locations more detailed")
      files = parser.add(positional: "<source-file>", kind: [PathArgument].self,
                         optional: false,
                         usage: "Swift source files to modify")
    }
  }
}

extension SwiftEvolveTool.Step.Options {
  fileprivate init(command: String, schema: SwiftEvolveTool.Step.ArgumentSchema, result: ArgumentParser.Result) {
    self.init(
      command: command,
      files: result.get(schema.files)!.map { $0.path },
      rulesFile: result.get(schema.rulesFile)?.path,
      replace: result.get(schema.replace) ?? false,
      verbose: result.get(schema.verbose) ?? false
    )
  }
}

// MARK: Argument generating

extension SwiftEvolveTool.Step: CustomStringConvertible {
  var arguments: [String] {
    switch self {
    case .parse(arguments: let arguments):
      return arguments
      
    case .seed(options: let options):
      return options.arguments(with: [])
      
    case let .plan(seed: seed, options: options):
      return options.arguments(with: ["--seed", String(seed)])
      
    case let .evolve(planFile: planFile, options: options):
      return options.arguments(with: ["--plan", planFile.pathString])
      
    case let .exit(code: status):
      return ["exit", String(status)]
    }
  }
  
  public var description: String {
    return arguments.map { $0.shellEscaped }.joined(separator: " ")
  }
}

extension SwiftEvolveTool.Step.Options {
  fileprivate func arguments(with stageArgs: [String]) -> [String] {
    var args = [command] + stageArgs
    if let rulesFile = rulesFile {
      args += ["--rules", rulesFile.pathString]
    }
    if replace {
      args += ["--replace"]
    }
    if verbose {
      args += ["--verbose"]
    }
    args += files.map { $0.pathString }
    return args
  }
}

extension String {
  fileprivate var shellEscaped: String {
    // FIXME This must perform horribly.
    return String(lazy.flatMap { shellSafe.contains($0) ? [$0] : ["\\", $0] })
  }
}

fileprivate let shellSafe =
  Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz01234556789_-=./")

// FIXME: Upstream this, possibly as an extension applicable to any
// LosslessStringConvertible type.
extension UInt64: ArgumentKind {
  public init(argument: String) throws {
    guard let int = UInt64(argument) else {
      throw ArgumentConversionError.typeMismatch(value: argument, expectedType: UInt64.self)
    }
    
    self = int
  }
  
  public static let completion: ShellCompletion = .none
}
