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
@testable import SwiftCWrapper
import Common

class SwiftCWrapperToolTests: XCTestCase {
  var workspace: URL!

  var testStressTesterPath: String!
  var testSwiftCPath: String!
  var testSwiftCWrapperPath: String!
  var testFilePath: String!
  var testInvocationPath: String!
  var errorJson: String!

  func testStatus() throws {
    typealias WrapperSpec = (compilerExit: Int32, stressTesterExit: Int32, expectedExit: Int32)
    let specs: [WrapperSpec] = [
      (compilerExit: 2, stressTesterExit: 1, expectedExit: 2),
      (compilerExit: 0, stressTesterExit: 1, expectedExit: 1),
      (compilerExit: 0, stressTesterExit: 0, expectedExit: 0),
      (compilerExit: 0, stressTesterExit: 6, expectedExit: 1)
    ]

    let environment: [String: String] = ["SK_STRESS_SWIFTC": testSwiftCPath]
    try specs.forEach { spec in
      let stdout = spec.stressTesterExit != 0 ? errorJson : nil
      makeScript(atPath: testStressTesterPath, exitCode: spec.stressTesterExit, stdout: stdout)
      makeScript(atPath: testSwiftCPath, exitCode: spec.compilerExit)

      let singleFileArgs: [String] = [testSwiftCWrapperPath, testFilePath]
      let wrapper = SwiftCWrapperTool(arguments: singleFileArgs, environment: environment)
      XCTAssertNoThrow(XCTAssertEqual(try wrapper.run(), spec.expectedExit))
    }
  }

  func testSilent() throws {
    typealias WrapperSpec = (compilerExit: Int32, stressTesterExit: Int32, expectedExit: Int32, silent: Bool)
    let specs: [WrapperSpec] = [
      (compilerExit: 2, stressTesterExit: 1, expectedExit: 2, silent: false),
      (compilerExit: 2, stressTesterExit: 1, expectedExit: 2, silent: true),
      (compilerExit: 0, stressTesterExit: 1, expectedExit: 1, silent: false),
      (compilerExit: 0, stressTesterExit: 1, expectedExit: 0, silent: true),
      (compilerExit: 0, stressTesterExit: 0, expectedExit: 0, silent: true),
      (compilerExit: 0, stressTesterExit: 0, expectedExit: 0, silent: false)
    ]

    let environment: [String: String] = ["SK_STRESS_SWIFTC": testSwiftCPath]
    try specs.forEach { spec in
      let stdout = spec.stressTesterExit != 0 ? errorJson : nil
      makeScript(atPath: testStressTesterPath, exitCode: spec.stressTesterExit, stdout: stdout)
      makeScript(atPath: testSwiftCPath, exitCode: spec.compilerExit)

      let singleFileArgs: [String] = [testSwiftCWrapperPath, testFilePath]
      let environment = environment.merging(["SK_STRESS_SILENT": String(spec.silent)]) { _, new in new }
      let wrapper = SwiftCWrapperTool(arguments: singleFileArgs, environment: environment)
      XCTAssertNoThrow(XCTAssertEqual(try wrapper.run(), spec.expectedExit))
    }
  }

  func testFailFastOperationQueue() throws {
    class TestOperation: Operation {
      var waitCount: Int

      init(waitCount: Int) {
        self.waitCount = waitCount
      }

      override func main() {
        while !isCancelled, waitCount > 0 {
          usleep(100)
          waitCount -= 1
        }
      }
    }

    let first = TestOperation(waitCount: 0)
    let second = TestOperation(waitCount: 10)
    let third = TestOperation(waitCount: 20)
    let fourth = TestOperation(waitCount: 30)

    FailFastOperationQueue(operations: [first, second, third, fourth], maxWorkers: 2, completionHandler: { finishedOp, _, _ in
      // cancel later operations when the second operation completes
      return finishedOp !== second
    }).waitUntilFinished()

    XCTAssertTrue(!first.isCancelled, "first was cancelled")
    XCTAssertTrue(!second.isCancelled, "second was cancelled")
    XCTAssertTrue(third.isCancelled, "third wasn't cancelled")
    XCTAssertTrue(fourth.isCancelled, "fourth wasn't cancelled")
  }

  func testEnvParsing() {
    makeScript(atPath: testSwiftCPath, exitCode: 0)
    makeScript(atPath: testStressTesterPath, exitCode: 0, recordInvocationIn: testInvocationPath)

    let defaultEnvironment: [String: String] = [
      "SK_STRESS_SWIFTC": testSwiftCPath,
      "SK_STRESS_TEST": testStressTesterPath,
    ]

    // check the produced invocations with default settings
    let singleFileArgs: [String] = [testSwiftCWrapperPath, testFilePath]
    XCTAssertNoThrow(XCTAssertEqual(try SwiftCWrapperTool(arguments: singleFileArgs, environment: defaultEnvironment).run(), 0))

    let defaultInvocations = try! String(contentsOf: URL(fileURLWithPath: testInvocationPath)).split(separator: "\n")
    let defaultExpected = [
      "--format json --page 1/1 --rewrite-mode none --request CursorInfo --request RangeInfo --request CodeComplete --request CollectExpressionType \(testFilePath!) swiftc \(testFilePath!)",
      "--format json --page 1/1 --rewrite-mode concurrent --request CursorInfo --request RangeInfo --request CodeComplete --request CollectExpressionType \(testFilePath!) swiftc \(testFilePath!)",
      "--format json --page 1/1 --rewrite-mode insideOut --request CursorInfo --request RangeInfo --request CodeComplete --request CollectExpressionType \(testFilePath!) swiftc \(testFilePath!)"
    ]

    XCTAssertEqual(defaultExpected.count, defaultInvocations.count)
    for invocation in defaultInvocations {
      XCTAssertTrue(defaultExpected.contains(String(invocation)))
    }

    // check custom request kinds and rewrite modes are propagated through correctly
    try! FileManager.default.removeItem(atPath: testInvocationPath)
    let customEnvironment = defaultEnvironment.merging([
      "SK_STRESS_REQUESTS": "CursorInfo RangeInfo CodeComplete TypeContextInfo ConformingMethodList CollectExpressionType all",
      "SK_STRESS_REWRITE_MODES": "basic insideOut",
      "SK_STRESS_CONFORMING_METHOD_TYPES": "s:SomeUSR s:OtherUSR s:ThirdUSR"
    ], uniquingKeysWith: { _, new in new })
    XCTAssertNoThrow(XCTAssertEqual(try SwiftCWrapperTool(arguments: singleFileArgs, environment: customEnvironment).run(), 0))

    let customInvocations = try! String(contentsOf: URL(fileURLWithPath: testInvocationPath)).split(separator: "\n")
    let customExpected = [
      "--format json --page 1/1 --rewrite-mode basic --request CursorInfo --request RangeInfo --request CodeComplete --request TypeContextInfo --request ConformingMethodList --request CollectExpressionType --request All --type-list-item s:SomeUSR --type-list-item s:OtherUSR --type-list-item s:ThirdUSR \(testFilePath!) swiftc \(testFilePath!)",
      "--format json --page 1/1 --rewrite-mode insideOut --request CursorInfo --request RangeInfo --request CodeComplete --request TypeContextInfo --request ConformingMethodList --request CollectExpressionType --request All --type-list-item s:SomeUSR --type-list-item s:OtherUSR --type-list-item s:ThirdUSR \(testFilePath!) swiftc \(testFilePath!)"
    ]
    XCTAssertEqual(customExpected.count, customInvocations.count)
    for invocation in customInvocations {
      XCTAssertTrue(customExpected.contains(String(invocation)), "Unexpected invocation: \(invocation)")
    }
  }

  func testIssueManager() {
    let xfail = ExpectedIssue(
      applicableConfigs: ["master"], issueUrl: "<issue-url>",
      path: "*/foo/bar.swift", modification: nil,
      issueDetail: .editorReplaceText(offset: 42, length: 0, text: nil)
    )

    let xfail2 = ExpectedIssue(
      applicableConfigs: ["master"], issueUrl: "<issue-url",
      path: "*/foo/bar.swift", modification: nil,
      issueDetail: .stressTesterCrash(status: 2, arguments: "*concurrent*"))

    let document1 = DocumentInfo(path: "/baz/foo/bar.swift", modification: nil)
    let request1 = RequestInfo.editorReplaceText(document: document1, offset: 42, length: 0, text: ".")
    let error1 = SourceKitError.crashed(request: request1)
    let issue1 = StressTesterIssue.failed(error1)

    let request2 = RequestInfo.editorReplaceText(document: document1, offset: 42, length: 2, text: "hello")
    let error2 = SourceKitError.crashed(request: request2)
    let issue2 = StressTesterIssue.failed(error2)

    let document2 = DocumentInfo(path: "/baz/bar.swift", modification: nil)
    let request3 = RequestInfo.editorReplaceText(document: document2, offset: 42, length: 0, text: ".")
    let error3 = SourceKitError.crashed(request: request3)
    let issue3 = StressTesterIssue.failed(error3)

    let error4 = SourceKitError.failed(.errorResponse, request: request1, response: "foo")
    let issue4 = StressTesterIssue.failed(error4)

    let issue5 = StressTesterIssue.errored(status: 2, file: "/bob/foo/bar.swift",
                                          arguments: "--rewrite-mode concurrent /bob/foo/bar.swift swiftc /bob/foo/bar.swift")
    let issue6 = StressTesterIssue.errored(status: 2,
                                            file: "/bob/foo/bar.swift",
                                            arguments: "--rewrite-mode basic /bob/foo/bar.swift swiftc /bob/foo/bar.swift")

    XCTAssertTrue(xfail.matches(issue1))
    XCTAssertFalse(xfail.matches(issue2))
    XCTAssertFalse(xfail.matches(issue3))
    XCTAssertTrue(xfail.matches(issue4))
    XCTAssertTrue(xfail2.matches(issue5))
    XCTAssertFalse(xfail2.matches(issue6))
  }

  override func setUp() {
    super.setUp()

    workspace = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("StressTesterToolTests", isDirectory: true)

    try? FileManager.default.removeItem(at: workspace)
    try! FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)

    testSwiftCWrapperPath = workspace
      .appendingPathComponent("sk-swiftc-wrapper", isDirectory: false)
      .path
    testSwiftCPath = workspace
      .appendingPathComponent("swiftc", isDirectory: false)
      .path
    testStressTesterPath = workspace
      .appendingPathComponent("sk-stress-test", isDirectory: false)
      .path
    testFilePath = workspace
      .appendingPathComponent("test.swift", isDirectory: false)
      .path
    testInvocationPath = workspace
      .appendingPathComponent("invocations.txt", isDirectory: false)
      .path
    errorJson = """
      {"message": "detected", "error": {
        "error": "timedOut",
        "request": {
          "document": {"path":"\(testFilePath!)"},
          "offset": 5,
          "args": ["\(testFilePath!)"],
          "request": "cursorInfo"
        }
      }}
      """

    FileManager.default.createFile(atPath: testFilePath, contents: """
      func square(_ x: Int) -> Int {
        return x * x
      }
      print(square(9))
      """.data(using: .utf8))
  }

  func makeScript(atPath path: String, exitCode: Int32, stdout: String? = nil, stderr: String? = nil, recordInvocationIn invocationPath: String? = nil) {
    var lines = ["#!/usr/bin/env bash"]
    if let stdout = stdout {
      lines.append("echo '\(stdout)'")
    }
    if let stderr = stderr {
      lines.append("echo '\(stderr)' >&2")
    }
    if let invocationPath = invocationPath {
      lines.append("echo $@ >> \(invocationPath)")
    }
    lines.append("exit \(exitCode)")
    let content = lines.joined(separator: "\n").data(using: .utf8)

    FileManager.default.createFile(atPath: path, contents: content, attributes: [FileAttributeKey.posixPermissions: 0o0755])
  }
}
