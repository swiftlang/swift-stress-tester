import XCTest
@testable import SwiftEvolve
import Basic

class CommandLineTests: XCTestCase {
  func file(named name: String) -> AbsolutePath {
    return localFileSystem.currentWorkingDirectory!.appending(component: name)
  }
  
  func testEmpty() throws {
    XCTAssertThrowsError(try SwiftEvolveTool.Step(arguments: ["exec-path"])) { error in
      XCTAssertEqual(String(describing: error), "expected arguments: <source-file>")
    }
  }
  
  func testDefaultsOneFile() throws {
    XCTAssertEqual(
      try SwiftEvolveTool.Step(arguments: ["exec-path", "file1.swift"]),
      .seed(options: .init(
        command: "exec-path",
        files: [file(named: "file1.swift")],
        rulesFile: nil,
        replace: false,
        verbose: false
      ))
    )
  }
  
  func testDefaultsTwoFiles() throws {
    XCTAssertEqual(
      try SwiftEvolveTool.Step(arguments: ["exec-path", "file1.swift", "file2.swift"]),
      .seed(options: .init(
        command: "exec-path",
        files: [file(named: "file1.swift"), file(named: "file2.swift")],
        rulesFile: nil,
        replace: false,
        verbose: false
      ))
    )
  }
  
  func testRulesFile() throws {
    XCTAssertEqual(
      try SwiftEvolveTool.Step(arguments: ["exec-path", "--rules", "rules.json", "file1.swift"]),
      .seed(options: .init(
        command: "exec-path",
        files: [file(named: "file1.swift")],
        rulesFile: file(named: "rules.json"),
        replace: false,
        verbose: false
      ))
    )
    
    XCTAssertEqual(
      try SwiftEvolveTool.Step(arguments: ["exec-path", "--rules=rules.json", "file1.swift"]),
      .seed(options: .init(
        command: "exec-path",
        files: [file(named: "file1.swift")],
        rulesFile: file(named: "rules.json"),
        replace: false,
        verbose: false
      ))
    )
    
    XCTAssertEqual(
      try SwiftEvolveTool.Step(arguments: ["exec-path", "--rules=rules.json", "--rules=other.json", "file1.swift"]),
      .seed(options: .init(
        command: "exec-path",
        files: [file(named: "file1.swift")],
        rulesFile: file(named: "other.json"),
        replace: false,
        verbose: false
      ))
    )

  }
  
  func testReplace() throws {
    XCTAssertEqual(
      try SwiftEvolveTool.Step(arguments: ["exec-path", "--replace", "file1.swift"]),
      .seed(options: .init(
        command: "exec-path",
        files: [file(named: "file1.swift")],
        rulesFile: nil,
        replace: true,
        verbose: false
      ))
    )
  }

  func testVerbose() throws {
    XCTAssertEqual(
      try SwiftEvolveTool.Step(arguments: ["exec-path", "--verbose", "file1.swift"]),
      .seed(options: .init(
        command: "exec-path",
        files: [file(named: "file1.swift")],
        rulesFile: nil,
        replace: false,
        verbose: true
      ))
    )

    SwiftEvolveTool.Step.Options(command: "exec-path",
                                 files: [file(named: "file1.swift")],
                                 rulesFile: nil,
                                 replace: false,
                                 verbose: true).setMinimumLogTypeToPrint()
    XCTAssertEqual(LogType.minimumToPrint, .debug)

    SwiftEvolveTool.Step.Options(command: "exec-path",
                                 files: [file(named: "file1.swift")],
                                 rulesFile: nil,
                                 replace: false,
                                 verbose: false).setMinimumLogTypeToPrint()
    XCTAssertEqual(LogType.minimumToPrint, .info)
  }
  
  func testSeed() throws {
    XCTAssertEqual(
      try SwiftEvolveTool.Step(arguments: ["exec-path", "--seed", "42", "file1.swift"]),
      .plan(seed: 42, options: .init(
        command: "exec-path",
        files: [file(named: "file1.swift")],
        rulesFile: nil,
        replace: false,
        verbose: false
      ))
    )
    
    XCTAssertEqual(
      try SwiftEvolveTool.Step(arguments: ["exec-path", "--seed=42", "file1.swift"]),
      .plan(seed: 42, options: .init(
        command: "exec-path",
        files: [file(named: "file1.swift")],
        rulesFile: nil,
        replace: false,
        verbose: false
      ))
    )
    
    XCTAssertThrowsError(
      try SwiftEvolveTool.Step(arguments: ["exec-path", "--seed", "file1.swift"])
    ) { error in
      XCTAssertEqual(String(describing: error).split(separator: ";").first,
                     "'file1.swift' is not convertible to UInt64 for argument --seed")
    }
  }
  
  func testPlan() throws {
    XCTAssertEqual(
      try SwiftEvolveTool.Step(arguments: ["exec-path", "--plan", "plan.json", "file1.swift"]),
      .evolve(planFile: file(named: "plan.json"), options: .init(
        command: "exec-path",
        files: [file(named: "file1.swift")],
        rulesFile: nil,
        replace: false,
        verbose: false
      ))
    )
    
    XCTAssertEqual(
      try SwiftEvolveTool.Step(arguments: ["exec-path", "--plan=plan.json", "file1.swift"]),
      .evolve(planFile: file(named: "plan.json"), options: .init(
        command: "exec-path",
        files: [file(named: "file1.swift")],
        rulesFile: nil,
        replace: false,
        verbose: false
      ))
    )
    
    XCTAssertThrowsError(
      try SwiftEvolveTool.Step(arguments: ["exec-path", "--seed=42", "--plan=plan.json", "file1.swift"])
    ) { error in
      XCTAssertEqual(String(describing: error),
                     "cannot specify both --seed and --plan; they are mutually exclusive")
    }
  }
}
