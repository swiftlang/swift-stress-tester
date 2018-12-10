import XCTest
import SwiftSyntax
@testable import SwiftEvolveKit

class RegressionTests: XCTestCase {
  var unusedRNG = UnusedGenerator()

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

      for node in code.filter(whereIs: MemberDeclListSyntax.self) {
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

  func testStoredIfConfigBlocksMemberwiseInitSynthesis() throws {
    try SyntaxTreeParser.withParsedCode(
      """
      struct A {
        #if os(iOS)
          var a1: Int
        #endif
        var a2: Int { fatalError() }
      }
      """
    ) { code in
      for decl in code.filter(whereIs: StructDeclSyntax.self) {
        let dc = DeclContext(declarationChain: [code, decl])

        XCTAssertThrowsError(
          try SynthesizeMemberwiseInitializerEvolution(
            for: decl.members.members, in: dc, using: &unusedRNG
          ),
          "Should throw when a stored property is in a #if block"
        )

        for ifConfig in decl.filter(whereIs: IfConfigDeclSyntax.self) {
          let dc = DeclContext(declarationChain: [code, decl])

          XCTAssertNil(
            try SynthesizeMemberwiseInitializerEvolution(
              for: (ifConfig.clauses.first!.elements as! MemberDeclListSyntax),
              in: dc, using: &unusedRNG
            ),
            "Should not try to synthesize an init() inside an #if"
          )
        }
      }
    }

    try SyntaxTreeParser.withParsedCode(
      """
      struct B {
        var b1: Int
        #if os(iOS)
          var b2: Int { fatalError() }
        #endif
      }
      """
    ) { code in
      for decl in code.filter(whereIs: StructDeclSyntax.self) {
        let dc = DeclContext(declarationChain: [code, decl])

        XCTAssertNoThrow(
          try SynthesizeMemberwiseInitializerEvolution(
            for: decl.members.members, in: dc, using: &unusedRNG
          ),
          "Should not throw when properties are only non-stored"
        )

        for ifConfig in decl.filter(whereIs: IfConfigDeclSyntax.self) {
          let dc = DeclContext(declarationChain: [code, decl])

          XCTAssertNil(
            try SynthesizeMemberwiseInitializerEvolution(
              for: (ifConfig.clauses.first!.elements as! MemberDeclListSyntax),
              in: dc, using: &unusedRNG
            ),
            "Should not try to synthesize an init() inside an #if"
          )
        }
      }
    }

    try SyntaxTreeParser.withParsedCode(
      """
      struct C {
        #if os(iOS)
          var c1: Int
        #endif
        var c2: Int { fatalError() }
        init() { c1 = 1 }
      }
      """
    ) { code in
      for decl in code.filter(whereIs: StructDeclSyntax.self) {
        let dc = DeclContext(declarationChain: [code, decl])

        XCTAssertNoThrow(
          try SynthesizeMemberwiseInitializerEvolution(
            for: decl.members.members, in: dc, using: &unusedRNG
          ),
          "Should not throw when there's an explicit init"
        )

        for ifConfig in decl.filter(whereIs: IfConfigDeclSyntax.self) {
          let dc = DeclContext(declarationChain: [code, decl])

          XCTAssertNil(
            try SynthesizeMemberwiseInitializerEvolution(
              for: (ifConfig.clauses.first!.elements as! MemberDeclListSyntax),
              in: dc, using: &unusedRNG
            ),
            "Should not try to synthesize an init() inside an #if"
          )
        }
      }
    }
  }
}
