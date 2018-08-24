//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

extension Collection {

  public func divide(into pieces: Int) -> [SubSequence] {
    func range(of piece: Int) -> Range<Index> {
      let start = index(startIndex, offsetBy: count * piece / pieces)
      let end = index(startIndex, offsetBy: count * (piece + 1) / pieces)
      return start..<end
    }
    return (0..<pieces).map {piece in self[range(of: piece)]}
  }
}
