import XCTest
import SwiftSyntax
import SwiftEvolve
import TSCBasic

extension SyntaxProtocol {
  func filter<T: SyntaxProtocol>(whereIs type: T.Type) -> [T] {
    let visitor = FilterVisitor { $0.is(T.self) }
    visitor.walk(self)
    return visitor.passing.map { $0.as(T.self)! }
  }
}

class FilterVisitor: SyntaxAnyVisitor {
  let predicate: (Syntax) -> Bool
  var passing: [Syntax] = []

  init(predicate: @escaping (Syntax) -> Bool) {
    self.predicate = predicate
  }

  override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
    if predicate(node) { passing.append(node) }
    return .visitChildren
  }
}

struct UnusedGenerator: RandomNumberGenerator {
  mutating func next() -> UInt64 {
    XCTFail("RNG used unexpectedly")
    return 0
  }
}

struct PredictableGenerator: RandomNumberGenerator {
  let values: [UInt64]
  var index: Int = 0

  init<S>(values: S) where S: Sequence, S.Element == UInt64 {
    self.values = Array(values)
  }

  mutating func next() -> UInt64 {
    defer {
      index = (index + 1) % values.count
    }
    return values[index]
  }
}
