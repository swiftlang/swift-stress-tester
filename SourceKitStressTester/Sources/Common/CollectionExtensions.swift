//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
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

  public func divide<T: Equatable>(by comparison: (Element) -> T) -> [SubSequence] {
    var working = self[...]
    var result = [SubSequence]()
    while let first = working.first {
      let firstValue = comparison(first)
      let partition = working.prefix{ comparison($0) == firstValue }
      result.append(partition)
      working = working.dropFirst(partition.count)
    }
    return result
  }
}
