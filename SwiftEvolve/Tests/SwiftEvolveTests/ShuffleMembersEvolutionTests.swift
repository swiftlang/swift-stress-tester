import XCTest
import SwiftSyntax
import SwiftSyntaxParser
import SwiftEvolve

class ShuffleMembersEvolutionTests: XCTestCase {
  var predictableRNG = PredictableGenerator(values: 0..<16)

  func testEnumCases() throws {
    let code = try SyntaxParser.parse(source:
      """
      enum Foo {
        case a
        case b
        func x() -> Int { return 0 }
      }
      """
    )
    let decl = code.filter(whereIs: EnumDeclSyntax.self).first!
    let dc = DeclContext(declarationChain: [code, decl])
    let evo = try ShuffleMembersEvolution(
      for: Syntax(decl.members.members), in: dc, using: &predictableRNG
    )

    XCTAssertEqual(evo?.mapping.count, 3)
  }
}
