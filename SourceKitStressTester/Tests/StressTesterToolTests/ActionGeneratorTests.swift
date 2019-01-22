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

import Foundation
import XCTest
@testable import StressTester
import SwiftLang
import Common

class ActionGeneratorTests: XCTestCase {
  var workspace: URL!
  var testFile: URL!
  var testFileContent: String!

  func testRequestActionGenerator() {
    let actions = RequestActionGenerator().generate(for: testFile)
    verify(actions, rewriteMode: .none)
  }

  func testRewriteActionGenerator() {
    let actions = RewriteActionGenerator().generate(for: testFile)
    verify(actions, rewriteMode: .basic)
  }

  func testConcurrentRewriteActionGenerator() {
    let actions = ConcurrentRewriteActionGenerator().generate(for: testFile)
    verify(actions, rewriteMode: .concurrent)
  }

  func testInsideOutActionGenerator() {
    let actions = InsideOutRewriteActionGenerator().generate(for: testFile)
    verify(actions, rewriteMode: .insideOut)
  }

  func testRequests() {
    let actions = RequestActionGenerator().generate(forContent: "var x = 2")
    let expected: [Action] = [
      .cursorInfo(position: SourcePosition(offset: 4, line: 1, column: 5)),
      .codeComplete(position: SourcePosition(offset: 5, line: 1, column: 6)),
      .rangeInfo(range: SourceRange(
        start: SourcePosition(offset: 6, line: 1, column: 7),
        end: SourcePosition(offset: 9, line: 1, column: 10),
        length: 3)),
      .rangeInfo(range: SourceRange(
        start: SourcePosition(offset: 4, line: 1, column: 5),
        end: SourcePosition(offset: 9, line: 1, column: 10),
        length: 5)),
      .rangeInfo(range: SourceRange(
        start: SourcePosition(offset: 0, line: 1, column: 1),
        end: SourcePosition(offset: 9, line: 1, column: 10),
        length: 9))
    ]
    XCTAssertEqual(actions, expected)
  }

  func verify(_ actions: [Action], rewriteMode: RewriteMode) {
    var state = SourceState(rewriteMode: rewriteMode, content: testFileContent)

    for action in actions {
      switch action {
      case .cursorInfo(let position):
        verify(position, in: state.source)
      case .codeComplete(let position):
        verify(position, in: state.source)
      case .rangeInfo(let range):
        verify(range.start, in: state.source)
        verify(range.end, in: state.source)
      case .replaceText(let range, let text):
        verify(range.start, in: state.source)
        verify(range.end, in: state.source)
        state.replace(range, with: text)
      }
    }
    XCTAssertEqual(state.source, testFileContent)
  }

  func verify(_ position: SourcePosition, in source: String) {
    if position.offset == 0 {
      XCTAssertEqual(position.line, 1)
      XCTAssertEqual(position.column, 1)
      return
    }

    var newLines = 0
    var columnsAtLastLine = 0
    var utf8Length = 0

    for char in source {
      let charLength = String(char).utf8.count
      utf8Length += charLength
      switch char {
      case "\n", "\r\n", "\r":
        newLines += 1
        columnsAtLastLine = 0
      default:
        columnsAtLastLine += charLength
      }

      if utf8Length == position.offset || (newLines + 1 == position.line && columnsAtLastLine + 1 == position.column) {
        XCTAssertEqual(position.offset, utf8Length, "offset doesn't match line and column")
        XCTAssertEqual(position.line, newLines + 1, "line doesn't match offset")
        XCTAssertEqual(position.column, columnsAtLastLine + 1, "column doesn't match")
        return
      }
    }

    XCTFail("position (offset: \(position.offset), line: \(position.line), col: \(position.column)) not in file")
  }

  override func setUp() {
    super.setUp()

    workspace = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("ActionGeneratorTests", isDirectory: true)

    try? FileManager.default.removeItem(at: workspace)
    try! FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)

    testFile = workspace
      .appendingPathComponent("test.swift", isDirectory: false)

    testFileContent = """
      func minMax(array: [Int]) -> (min: Int, max: Int) {
          var currentMin = array[0]
          var currentMax = array[0]
          for value in array[1..<array.count] {
              if value < currentMin {
                  currentMin = value
              } else if value > currentMax {
                  currentMax = value
              }
          }
          return (currentMin, currentMax)
      }

      let result = minMax(array: [10, 43, 1, 2018])
      print("range: \\(result.min) – \\(result.max)")
      """

    FileManager.default.createFile(atPath: testFile.path, contents: testFileContent.data(using: .utf8))
  }
}

extension ActionGenerator {
  func generate(forContent content: String) -> [Action] {
    let tempFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("ActionGeneratorTests", isDirectory: true)
      .appendingPathComponent("temp.swift", isDirectory: false)
    FileManager.default.createFile(atPath: tempFile.path, contents: content.data(using: .utf8))
    return generate(for: tempFile)
  }
}
