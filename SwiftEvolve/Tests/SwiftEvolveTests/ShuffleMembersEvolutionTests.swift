import XCTest
import SwiftSyntax
import SwiftLang
@testable import SwiftEvolve

class ShuffleMembersEvolutionTests: XCTestCase {
  var predictableRNG = PredictableGenerator(values: 0..<16)

  func testEnumCases() throws {
    try SwiftLang.withParsedCode(
      """
      enum Foo {
        case a
        case b
        func x() -> Int { return 0 }
      }
      """
    ) { code in
      let decl = code.filter(whereIs: EnumDeclSyntax.self).first!
      let dc = DeclContext(declarationChain: [code, decl])
      let evo = try ShuffleMembersEvolution(
        for: decl.members.members, in: dc, using: &predictableRNG
      )

      XCTAssertEqual(evo?.mapping.count, 3)
    }
  }
}
