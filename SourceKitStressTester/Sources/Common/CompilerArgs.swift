//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

public struct CompilerArg: Equatable {
  /// The original argument as passed
  public let original: String

  /// If the argument is a file list (@/some/file), this is the arguments
  /// parsed from that file. Otherwise it is an array of a single value - the
  /// original argument.
  public let transformed: [String]

  public init(_ argument: String) {
    self.original = argument
    self.transformed = fileListArgs(arg: argument)
      .map({ args in
        args.map({ $0.replacingOccurrences(of: "\\ ", with: " ") })
      }) ?? [argument]
  }
}

public struct CompilerArgs {
  private static let SKIP_FLAGS: Set = [
    "-whole-module-optimization",
    "-incremental"
  ]
  private static let SKIP_OPTIONS: Set = [
    "-num-threads",
    "-output-file-map"
  ]

  /// Main file intended to be compiled
  public let forFile: URL

  /// Original arguments as passed
  public let original: [String]

  /// Arguments with any file list arguments (@file) replaced with the
  /// arguments found in those files
  public let sourcekitdArgs: [String]

  /// Original arguments but with flags/options relating to multi-module
  /// output removed, as well as any references to fileToCompile. This
  /// includes replacing any file list with a new file when they contain the
  /// fileToCompile
  public let processArgs: [String]

  public init(for file: URL, args: [CompilerArg], tempDir: URL) {
    self.forFile = file
    self.original = args.map { $0.original }
    self.sourcekitdArgs = args.flatMap { $0.transformed }

    var processArgs = [String]()
    var skip = false
    for arg in args {
      if skip {
        skip = false
        continue;
      }

      if arg.original == file.path {
        continue
      }

      if CompilerArgs.SKIP_FLAGS.contains(arg.original) {
        continue
      }

      if CompilerArgs.SKIP_OPTIONS.contains(arg.original) {
        skip = true
        continue
      }

      if let listArgs = fileListArgs(arg: arg.original) {
        let fileRemoved = listArgs.filter { $0 != file.path }
        if fileRemoved.count != listArgs.count {
          let newFileList = tempDir.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("SwiftFileList")
          let data = Data(fileRemoved.joined(separator: "\n").utf8)
          try! data.write(to: newFileList)
          processArgs.append("@" + newFileList.path)
        }

        continue
      }

      processArgs.append(arg.original)
    }
    self.processArgs = processArgs
  }
}

func fileListArgs(arg: String) -> [String]? {
  guard arg.starts(with: "@") else {
    return nil
  }

  let url = URL(fileURLWithPath: String(arg.dropFirst()) , isDirectory: false)
  if let content = try? String(contentsOf: url, encoding: .utf8) {
    return content.split(separator: "\n").map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }
  return nil
}
