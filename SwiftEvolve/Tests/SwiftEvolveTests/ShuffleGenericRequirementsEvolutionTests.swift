import XCTest
import SwiftSyntax
import SwiftParser
import SwiftEvolve

class ShuffleGenericRequirementsEvolutionTests: XCTestCase {
  var predictableRNG = PredictableGenerator(values: 1..<16)

  func testEvolution() throws {
    let code = Parser.parse(source:
      """
      func foo<T>(_: T) where T: Hashable, T == Comparable {}
      """
    )
    let decl = code.filter(whereIs: FunctionDeclSyntax.self).first!
    let dc = DeclContext(declarationChain: [code, decl])

    let evo = try ShuffleGenericRequirementsEvolution(
      for: Syntax(decl.genericWhereClause!.requirements), in: dc, using: &predictableRNG
    )

    XCTAssertEqual(evo?.mapping.count, 2)

    let evolved = evo?.evolve(Syntax(decl.genericWhereClause!.requirements))
    // FIXME: disabled because of CI failure rdar://51635159
    // XCTAssertEqual(evolved.map(String.init(describing:)),
    //               "T == Comparable , T: Hashable")
  }

  func testBypass() {
    let code = Parser.parse(source:
      """
      func foo<T>(_: T) where T: Hashable, T == Comparable {}
      """
    )
    let decl = code.filter(whereIs: FunctionDeclSyntax.self).first!
    let dc = DeclContext(declarationChain: [code, decl])

    XCTAssertThrowsError(
      try ShuffleGenericRequirementsEvolution(
        for: Syntax(decl.genericWhereClause!), in: dc, using: &predictableRNG
      )
    ) { error in
      XCTAssertEqual(error as? EvolutionError, EvolutionError.unsupported)
    }
  }
}
