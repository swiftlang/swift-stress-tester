// SwiftEvolveKit/SyntaxTriviaExtensions.swift - SwiftSyntax trivia extensions
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
/// This file includes extensions to manipulate the trivia around an arbitrary
/// Syntax node.
///
// -----------------------------------------------------------------------------

import SwiftSyntax

extension SyntaxProtocol {
  func prependingComment(_ text: String) -> Self {
    return replacingTriviaWith(leading: {
      $0 + [.lineComment("// \(text)"), .newlines(1)] + $0.trailingIndentation
    })
  }
  
  func replacingTriviaWith(leading: (Trivia) -> Trivia = { $0 }, trailing: (Trivia) -> Trivia = { $0 }) -> Self {
    return withoutActuallyEscaping(trailing) { trailing in
      withoutActuallyEscaping(leading) { leading in
        SingleTokenRewriter(
          shouldRewrite: { $0 == ($0.parent?.children(viewMode: .sourceAccurate).last ?? $0) },
          transform: { $0.withTrailingTrivia(trailing($0.trailingTrivia)) }
        ).visit(
          SingleTokenRewriter(
            shouldRewrite: { $0 == ($0.parent?.children(viewMode: .sourceAccurate).first ?? $0) },
            transform: { $0.withLeadingTrivia(leading($0.leadingTrivia)) }
          ).visit(Syntax(self))
        ).as(Self.self)!
      }
    }
  }
  
  func replacingTriviaWith(leading: Trivia? = nil, trailing: Trivia? = nil) -> Self {
    return replacingTriviaWith(
      leading: { leading ?? $0 }, trailing: { trailing ?? $0 }
    )
  }
}

fileprivate extension SyntaxChildren {
  var first: Syntax? {
    for node in self {
      return node
    }
    return nil
  }
  
  var last: Syntax? {
    var value: Syntax? = nil
    for node in self {
      value = node
    }
    return value
  }
}

fileprivate class SingleTokenRewriter: SyntaxRewriter {
  init(shouldRewrite: @escaping (Syntax) -> Bool, transform: @escaping (TokenSyntax) -> TokenSyntax) {
    self.shouldRewrite = shouldRewrite
    self.transform = transform
  }
  
  let shouldRewrite: (Syntax) -> Bool
  let transform: (TokenSyntax) -> TokenSyntax
  
  override func visit(_ token: TokenSyntax) -> TokenSyntax {
    return transform(token)
  }
  
  override func visitAny(_ node: Syntax) -> Syntax? {
    if shouldRewrite(node) {
      // This is either the token we want or it contains the token we want.
      // In either case, recurse.
      return nil
    }
    else {
      // Ignore this node; it's not what we're looking for.
      return node
    }
  }
}

extension TriviaPiece {
  var isIndentation: Bool {
    switch self {
    case .spaces, .tabs:
      return true
    default:
      return false
    }
  }
}

extension Trivia {
  var trailingIndentation: Trivia {
    return Trivia(pieces: lazy.reversed().prefix { $0.isIndentation }.reversed())
  }
}
