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
      XCTAssertEqual(defaults.request, [.all])
      XCTAssertEqual(defaults.dryRun, false)
      XCTAssertEqual(defaults.reportResponses, false)
      XCTAssertEqual(defaults.conformingMethodsTypeList, ["s:SQ", "s:SH"])
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
      testFile.path, "--", testFile.path
    ]
    let assertValid = { [testFile] (args: [String]) in
      StressTesterToolTests.assertParse(args) { tool in
        XCTAssertEqual(tool.rewriteMode, .basic)
        XCTAssertEqual(tool.format, .json)
        XCTAssertEqual(tool.limit, 1)
        XCTAssertEqual(tool.page, Page(2, of: 5))
        XCTAssertEqual(tool.request, [.cursorInfo, .codeComplete])
        XCTAssertEqual(tool.dryRun, true)
        XCTAssertEqual(tool.reportResponses, true)
        XCTAssertEqual(tool.conformingMethodsTypeList, ["foo", "bar"])
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
                                      responseHandler: { responseData in
                                        responses.append(responseData)
                                      })

    let tester = StressTester(for: testFile, compilerArgs: [testFile.path],
                              options: options)
    XCTAssertNoThrow(try tester.run(),
                     "no sourcekitd crashes in test program")
    XCTAssertFalse(responses.isEmpty, "produces responses")
    XCTAssertTrue(responses.allSatisfy { response in
      if case .codeComplete = response.request { return true }
      return false
    }, "request filter is respected")
    XCTAssertFalse(responses.allSatisfy { $0.results.isEmpty }, "responses have results")
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
