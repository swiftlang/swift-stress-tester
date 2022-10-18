import XCTest
import SwiftSyntax
import SwiftSyntaxParser
import SwiftEvolve

class RegressionTests: XCTestCase {
  var unusedRNG = UnusedGenerator()

  func testUnshuffledDeclsStayInOrder() throws {
    // Checks that we don't mess up the order of declarations we're not trying
    // to shuffle. In particular, if we store the properties in a Set or other
    // unordered collection, we could screw this up.
    let code = try SyntaxParser.parse(source:
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
    )
    let evo = ShuffleMembersEvolution(mapping: [])

    for node in code.filter(whereIs: MemberDeclListSyntax.self) {
      let evolved = evo.evolve(Syntax(node))
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

  func testStoredIfConfigBlocksMemberwiseInitSynthesis() throws {
    do {
      // FIXME: Crashes when run in Xcode because of a version mismatch between
      // SwiftSyntax and the compiler it uses (specifically, how they represent
      // accessor blocks). Should pass in "env PATH=... swift build".
      let code = try SyntaxParser.parse(source:
        """
        struct A {
          #if os(iOS)
            var a1: Int
          #endif
          var a2: Int { fatalError() }
        }
        """
      )
      for decl in code.filter(whereIs: StructDeclSyntax.self) {
        let dc = DeclContext(declarationChain: [code, decl])

        XCTAssertThrowsError(
          try SynthesizeMemberwiseInitializerEvolution(
            for: Syntax(decl.members.members), in: dc, using: &unusedRNG
          ),
          "Should throw when a stored property is in a #if block"
        )

        for ifConfig in decl.filter(whereIs: IfConfigDeclSyntax.self) {
          let dc = DeclContext(declarationChain: [code, decl])

          XCTAssertNil(
            try SynthesizeMemberwiseInitializerEvolution(
              for: (ifConfig.clauses.first!.elements!),
              in: dc, using: &unusedRNG
            ),
            "Should not try to synthesize an init() inside an #if"
          )
        }
      }
    }

    do {
      let code = try SyntaxParser.parse(source:
        """
        struct B {
          var b1: Int
          #if os(iOS)
            var b2: Int { fatalError() }
          #endif
        }
        """
      )
      for decl in code.filter(whereIs: StructDeclSyntax.self) {
        let dc = DeclContext(declarationChain: [code, decl])

        XCTAssertNoThrow(
          try SynthesizeMemberwiseInitializerEvolution(
            for: Syntax(decl.members.members), in: dc, using: &unusedRNG
          ),
          "Should not throw when properties are only non-stored"
        )

        for ifConfig in decl.filter(whereIs: IfConfigDeclSyntax.self) {
          let dc = DeclContext(declarationChain: [code, decl])

          XCTAssertNil(
            try SynthesizeMemberwiseInitializerEvolution(
              for: (ifConfig.clauses.first!.elements!),
              in: dc, using: &unusedRNG
            ),
            "Should not try to synthesize an init() inside an #if"
          )
        }
      }
    }

    do {
      let code = try SyntaxParser.parse(source:
        """
        struct C {
          #if os(iOS)
            var c1: Int
          #endif
          var c2: Int { fatalError() }
          init() { c1 = 1 }
        }
        """
      )
      for decl in code.filter(whereIs: StructDeclSyntax.self) {
        let dc = DeclContext(declarationChain: [code, decl])

        XCTAssertNoThrow(
          try SynthesizeMemberwiseInitializerEvolution(
            for: Syntax(decl.members.members), in: dc, using: &unusedRNG
          ),
          "Should not throw when there's an explicit init"
        )

        for ifConfig in decl.filter(whereIs: IfConfigDeclSyntax.self) {
          let dc = DeclContext(declarationChain: [code, decl])

          XCTAssertNil(
            try SynthesizeMemberwiseInitializerEvolution(
              for: (ifConfig.clauses.first!.elements!),
              in: dc, using: &unusedRNG
            ),
            "Should not try to synthesize an init() inside an #if"
          )
        }
      }
    }
  }
}
