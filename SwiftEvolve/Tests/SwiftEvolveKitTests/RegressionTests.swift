import XCTest
import SwiftSyntax
@testable import SwiftEvolveKit

class RegressionTests: XCTestCase {
    func testUnshuffledDeclsStayInOrder() throws {
      // Checks that we don't mess up the order of declarations we're not trying
      // to shuffle. In particular, if we store the properties in a Set or other
      // unordered collection, we could screw this up.
      try SyntaxTreeParser.withParsedCode(
        """
        @_fixed_layout struct X {
          var p0: Int
          var p1: Int
          var p2: Int
          var p3: Int
          var p4: Int
          var p5: Int
          var p6: Int
          var p7: Int
          var p8: Int
          var p9: Int
        }
        """
      ) { code in
        let evo = ShuffleMembersEvolution(mapping: [])
        code.withEach(whereIs: MemberDeclListSyntax.self) { node in
          let evolved = evo.evolve(node)
          let evolvedCode = evolved.description
          
          let locs = (0...9).compactMap {
            evolvedCode.range(of: "p\($0)")?.lowerBound
          }
          
          XCTAssertEqual(locs.count, 10, "All ten properties were preserved")
          
          for (prev, next) in zip(locs, locs.dropFirst()) {
            XCTAssertLessThan(prev, next, "Adjacent properties are in order")
          }
        }
      }
    }
}

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
  func withEach<T: Syntax>(whereIs type: T.Type, do body: (T) -> Void) {
    withoutActuallyEscaping(body) { body in
      let visitor = WithEachVisitor(
        predicate: { $0 is T }, body: { body($0 as! T) }
      )
      walk(visitor)
    }
  }
}

class WithEachVisitor: SyntaxVisitor {
  let predicate: (Syntax) -> Bool
  let body: (Syntax) -> Void
  
  init(predicate: @escaping (Syntax) -> Bool, body: @escaping (Syntax) -> Void) {
    self.predicate = predicate
    self.body = body
  }
  
  override func visitPre(_ node: Syntax) {
    if predicate(node) { body(node) }
  }
}
