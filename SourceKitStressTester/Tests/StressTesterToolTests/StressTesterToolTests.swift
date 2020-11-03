//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Common
import StressTester
import XCTest

class StressTesterToolTests: XCTestCase {
  var workspace: URL!
  var testFile: URL!
  var swiftcPath: String!

  func testCommandLine() {
    let valid: [String] = [testFile.path, "--", testFile.path]

    // No source file
    XCTAssertThrowsError(try StressTesterTool.parse([]))

    // No compiler args
    XCTAssertThrowsError(try StressTesterTool.parse([testFile.path]))

    // Defaults
    StressTesterToolTests.assertParse(valid) { defaults in
      XCTAssertEqual(defaults.rewriteMode, .none)
      XCTAssertEqual(defaults.format, .humanReadable)
      XCTAssertEqual(defaults.limit, nil)
      XCTAssertEqual(defaults.page, Page())
      XCTAssertEqual(defaults.request, [.ide])
      XCTAssertEqual(defaults.dryRun, false)
      XCTAssertEqual(defaults.reportResponses, false)
      XCTAssertEqual(defaults.conformingMethodsTypeList, ["s:SQ", "s:SH"])
      XCTAssertEqual(defaults.swiftc, swiftcPath)
      XCTAssertEqual(defaults.file, testFile)
      XCTAssertEqual(defaults.compilerArgs, [testFile.path])
    }

    let allLong: [String] = [
      "--rewrite-mode", "basic",
      "--format", "json",
      "--limit", "1",
      "--page", "2/5",
      "--request", "CursorInfo", "--request", "CODECOMPLETE",
      "--dry-run",
      "--report-responses",
      "--type-list-item", "foo", "--type-list-item", "bar",
      "--temp-dir", workspace.path,
      "--swiftc", swiftcPath,
      testFile.path, "--", testFile.path
    ]
    let allShort: [String] = [
      "-m", "basic",
      "-f", "json",
      "-l", "1",
      "-p", "2/5",
      "-r", "CursorInfo", "-r", "CODECOMPLETE",
      "-d",
      "--report-responses", // no short
      "-t", "foo", "-t", "bar",
      "--temp-dir", workspace.path, // no short
      "-s", swiftcPath,
      testFile.path, "--", testFile.path
    ]
    let assertValid = { [workspace, swiftcPath, testFile] (args: [String]) in
      StressTesterToolTests.assertParse(args) { tool in
        XCTAssertEqual(tool.rewriteMode, .basic)
        XCTAssertEqual(tool.format, .json)
        XCTAssertEqual(tool.limit, 1)
        XCTAssertEqual(tool.page, Page(2, of: 5))
        XCTAssertEqual(tool.request, [.cursorInfo, .codeComplete])
        XCTAssertEqual(tool.dryRun, true)
        XCTAssertEqual(tool.reportResponses, true)
        XCTAssertEqual(tool.conformingMethodsTypeList, ["foo", "bar"])
        XCTAssertEqual(tool.tempDir, workspace)
        XCTAssertEqual(tool.swiftc, swiftcPath)
        XCTAssertEqual(tool.file, testFile!)
        XCTAssertEqual(tool.compilerArgs, [testFile!.path])
      }
    }
    assertValid(allLong)
    assertValid(allShort)

    // Unknown flag
    XCTAssertThrowsError(try StressTesterTool.parse(["--not-an-option"] + valid))

    // Missing
    XCTAssertThrowsError(try StressTesterTool.parse(["--format"] + valid))

    // Unknown values
    XCTAssertThrowsError(try StressTesterTool.parse(["--format", "blah"] + valid))
    XCTAssertThrowsError(try StressTesterTool.parse(["--request", "Unknown"] + valid))
  }

  func testDumpResponses() {
    var responses = [SourceKitResponseData]()
    let options = StressTesterOptions(requests: .codeComplete,
                                      rewriteMode: .none,
                                      conformingMethodsTypeList: [],
                                      page: Page(),
                                      tempDir: workspace,
                                      responseHandler: { responseData in
                                        responses.append(responseData)
                                      })

    let tester = StressTester(options: options)
    XCTAssertNoThrow(try tester.run(for: testFile, swiftc: swiftcPath,
                                    compilerArgs: [testFile.path]),
                     "no sourcekitd crashes in test program")
    XCTAssertFalse(responses.isEmpty, "produces responses")
    XCTAssertTrue(responses.allSatisfy { response in
      if case .codeComplete = response.request { return true }
      return false
    }, "request filter is respected")
    XCTAssertFalse(responses.allSatisfy { $0.results.isEmpty }, "responses have results")
  }

  func testModuleRequest() {
    var addedActions = [Action]()
    let options = StressTesterOptions(requests: .testModule,
                                      rewriteMode: .none,
                                      conformingMethodsTypeList: [],
                                      page: Page(),
                                      tempDir: workspace,
                                      dryRun: { actions in
                                        addedActions.append(contentsOf: actions)
                                      })

    let tester = StressTester(options: options)
    try! tester.run(for: testFile, swiftc: swiftcPath,
                    compilerArgs: [testFile.path])

    XCTAssertFalse(addedActions.isEmpty, "produces actions")
    XCTAssertEqual(addedActions.last!, .testModule)
    XCTAssertTrue(addedActions[..<(addedActions.count - 1)].allSatisfy { action in
      if case .replaceText = action { return true }
      return false
    }, "request filter is respected")
  }

  override func setUp() {
    super.setUp()

    workspace = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("StressTesterToolTests", isDirectory: true)

    try? FileManager.default.removeItem(at: workspace)
    try! FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)

    testFile = workspace
      .appendingPathComponent("test.swift")

    FileManager.default.createFile(atPath: testFile.path, contents: """
      func square(_ x: Int) -> Int {
        return x * x
      }
      print(square(9))
      """.data(using: .utf8))

    swiftcPath = pathFromXcrun(for: "swiftc")
  }

  private static func assertParse(_ args: [String],
                                  file: StaticString = #file, line: UInt = #line,
                                  closure: (StressTesterTool) throws -> Void) {
    do {
      let parsed = try StressTesterTool.parse(args)
      try closure(parsed)
    } catch {
      let message = StressTesterTool.message(for: error)
      XCTFail("\"\(message)\" — \(error)", file: (file), line: line)
    }
  }
}
