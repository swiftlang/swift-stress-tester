// SwiftEvolveKit/SyntaxDump.swift - SwiftSyntax tree dumper
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
/// This file includes a type which can be used to dump a SwiftSyntax tree in
/// an S-expression-style format for humans to read.
///
// -----------------------------------------------------------------------------

import Foundation
import SwiftSyntax

/// Wraps a Syntax node so that printing it produces a human-readable
/// S-expression-style dump of it and its descendents.
struct SyntaxDump: TextOutputStreamable {
  let node: Syntax
  let locationConverter: SourceLocationConverter
  
  func write<Target>(_ node: Syntax, to target: inout Target, indentation: Int)
    where Target : TextOutputStream
  {
    func write(_ str: String) {
      let lines = str.split(separator: "\n", omittingEmptySubsequences: false)
      let newSeparator = "\n" + String(repeating: " ", count: indentation)
      target.write(lines.joined(separator: newSeparator))
    }
    
    func writeLoc(_ loc: SourceLocation?) {
      guard let loc = loc else { return }
      
      let url = URL(fileURLWithPath: loc.file)
      write(" ")
      write(url.lastPathComponent)
      write(":")
      write("\(loc.line)")
      write(":")
      write("\(loc.column)")
    }

    let startLoc = node.startLocation(converter: locationConverter)
    write("(")
    switch node {
    case let node as TokenSyntax:
      switch node.tokenKind {
      case .identifier(let name):
        write("identifier")
        write(" \"\(name)\"")
      default:
        write("\(node.tokenKind)")
      }
      writeLoc(startLoc)
      
    default:
      write("\(type(of: node))")
      writeLoc(startLoc)
      for child in node.children {
        write("\n  ")
        self.write(child, to: &target, indentation: indentation + 2)
      }
    }
    write(")")
  }
  
  func write<Target>(to target: inout Target) where Target : TextOutputStream {
    write(node, to: &target, indentation: 0)
  }
}
