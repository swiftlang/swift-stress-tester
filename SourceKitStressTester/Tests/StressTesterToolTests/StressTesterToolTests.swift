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

import XCTest
@testable import StressTester

class StressTesterToolTests: XCTestCase {
  var workspace: URL!

  var stressTesterPath: String!
  var testFilePath: String!

  func testCommandLine() {
    let noSourceFile: [String] = [stressTesterPath]
    XCTAssertThrowsError(try StressTesterTool(arguments: noSourceFile).parse())

    let noCompilerArgs: [String] = [stressTesterPath, testFilePath]
    XCTAssertThrowsError(try StressTesterTool(arguments: noCompilerArgs).parse())

    let validSuffix: [String] = [testFilePath, "swiftc", testFilePath]
    let valid = [stressTesterPath] + validSuffix
    XCTAssertNoThrow(try StressTesterTool(arguments: valid).parse())

    let invalidOptions = [stressTesterPath, "--not-an-option"] + validSuffix
    XCTAssertThrowsError(try StressTesterTool(arguments: invalidOptions).parse())

    let noValue = [stressTesterPath, "--format"] + validSuffix
    XCTAssertThrowsError(try StressTesterTool(arguments: noValue).parse())

    let unknownValue = [stressTesterPath, "--format", "blah"] + validSuffix
    XCTAssertThrowsError(try StressTesterTool(arguments: unknownValue).parse())

    let knownValue = [stressTesterPath, "--format", "json"] + validSuffix
    XCTAssertNoThrow(try StressTesterTool(arguments: knownValue).parse())

    let typeMismatch = [stressTesterPath, "--limit", "hello"] + validSuffix
    XCTAssertThrowsError(try StressTesterTool(arguments: typeMismatch).parse())

    let validLimit = [stressTesterPath, "--limit", "1"] + validSuffix
    XCTAssertNoThrow(try StressTesterTool(arguments: validLimit).parse())

    let invalidRequest = [stressTesterPath, "--request", "UnknownRequest"] + validSuffix
    XCTAssertThrowsError(try StressTesterTool(arguments: invalidRequest).parse())

    let validRequest1 = [stressTesterPath, "--request", "CursorInfo"] + validSuffix
    XCTAssertNoThrow(try StressTesterTool(arguments: validRequest1).parse())

    let validRequest2 = [stressTesterPath, "--request", "CURSORINFO"] + validSuffix
    XCTAssertNoThrow(try StressTesterTool(arguments: validRequest2).parse())
  }

  override func setUp() {
    super.setUp()

    workspace = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("StressTesterToolTests", isDirectory: true)

    try? FileManager.default.removeItem(at: workspace)
    try! FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)

    stressTesterPath = workspace
      .appendingPathComponent("sk-stress-test", isDirectory: false)
      .path
    testFilePath = workspace
      .appendingPathComponent("test.swift", isDirectory: false)
      .path

    FileManager.default.createFile(atPath: testFilePath, contents: """
      func square(_ x: Int) -> Int {
        return x * x
      }
      print(square(9))
      """.data(using: .utf8))
  }
}
