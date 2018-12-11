import XCTest
@testable import SwiftEvolveKit

class RulesTests: XCTestCase {
  let sharedRules = EvolutionRules(exclusions: [
    .shuffleMembers: nil,
    .synthesizeMemberwiseInitializer: ["(file).Foo.Bar", "(file).Baz"]
  ])
  
  func testDecoding() throws {
    let json = """
      {
        "shuffleMembers": null,
        "synthesizeMemberwiseInitializer": ["(file).Foo.Bar", "(file).Baz"]
      }
      """
    let rules = try JSONDecoder().decode(EvolutionRules.self,
                                         from: json.data(using: .utf8)!)
    XCTAssertEqual(rules.exclusions, sharedRules.exclusions)
  }
  
  func testPermit() {
    XCTAssertFalse(sharedRules.permit(.shuffleMembers, forDeclName: "(file).Foo"))
    XCTAssertFalse(sharedRules.permit(.shuffleMembers, forDeclName: "(file).Foo.Bar"))
    XCTAssertFalse(sharedRules.permit(.shuffleMembers, forDeclName: "(file).Baz"))
    XCTAssertFalse(sharedRules.permit(.shuffleMembers, forDeclName: "(file).Baz.Quux"))

    XCTAssertTrue(sharedRules.permit(.synthesizeMemberwiseInitializer, forDeclName: "(file).Foo"))
    XCTAssertFalse(sharedRules.permit(.synthesizeMemberwiseInitializer, forDeclName: "(file).Foo.Bar"))
    XCTAssertFalse(sharedRules.permit(.synthesizeMemberwiseInitializer, forDeclName: "(file).Baz"))
    XCTAssertTrue(sharedRules.permit(.synthesizeMemberwiseInitializer, forDeclName: "(file).Baz.Quux"))

    // FIXME: When we have a third evolution, use it in these tests.
//    XCTAssertTrue(sharedRules.permit(.changeDefaultArgument, forDeclName: "(file).Foo"))
//    XCTAssertTrue(sharedRules.permit(.changeDefaultArgument, forDeclName: "(file).Foo.Bar"))
//    XCTAssertTrue(sharedRules.permit(.changeDefaultArgument, forDeclName: "(file).Baz"))
//    XCTAssertTrue(sharedRules.permit(.changeDefaultArgument, forDeclName: "(file).Baz.Quux"))
  }
}
