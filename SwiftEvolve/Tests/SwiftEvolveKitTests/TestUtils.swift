import XCTest
import SwiftSyntax
@testable import SwiftEvolveKit

extension SyntaxTreeParser {
  static func withParsedCode(
    _ code: String, do body: (SourceFileSyntax) throws -> Void
    ) throws -> Void {
    let url = try code.write(toTemporaryFileWithPathExtension: "swift")
    defer {
      try? FileManager.default.removeItem(at: url)
    }
    try body(parse(url))
  }
}

extension Syntax {
  func filter<T: Syntax>(whereIs type: T.Type) -> [T] {
    let visitor = FilterVisitor { $0 is T }
    walk(visitor)
    return visitor.passing as! [T]
  }
}

class FilterVisitor: SyntaxVisitor {
  let predicate: (Syntax) -> Bool
  var passing: [Syntax] = []

  init(predicate: @escaping (Syntax) -> Bool) {
    self.predicate = predicate
  }

  override func visitPre(_ node: Syntax) {
    if predicate(node) { passing.append(node) }
  }
}

struct UnusedGenerator: RandomNumberGenerator {
  mutating func next<T>() -> T where T : FixedWidthInteger, T : UnsignedInteger {
    XCTFail("RNG used unexpectedly")
    return 0
  }
}
