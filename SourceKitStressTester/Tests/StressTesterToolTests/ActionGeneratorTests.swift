//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import XCTest
import StressTester
import SwiftSourceKit
import Common

class ActionGeneratorTests: XCTestCase {
  var workspace: URL!
  var testFile: URL!
  var testFileContent: String!

  private let ALL_ACTIONS: [Action.BaseAction] = [
    .format, .codeComplete, .cursorInfo, .rangeInfo, .conformingMethodList,
    .typeContextInfo, .collectExpressionType, .replaceText, .testModule]

  func testRequestActionGenerator() {
    let actions = RequestActionGenerator().generate(for: testFile)
    let expectedActions = ALL_ACTIONS.filter({ $0 != .replaceText })

    verify(actions, rewriteMode: .none, expectedActionTypes: expectedActions)

    XCTAssertEqual(actions.filter{
      if case .collectExpressionType = $0 { return true }
      return false
    }.count, 1, "there is a single CollectExpressionType action")

    XCTAssertEqual(actions.filter{
      if case .testModule = $0 { return true }
      return false
    }.count, 1, "there is a single TestModule action")

    // I=CursorInfo, C=CodeComplete, T=TypeContextInfo, M=ConformingMethodList, R=RangeInfo(start), E=RangeInfo(end)
    XCTAssertEqual(ActionMarkup(actions, in: testFileContent).markedUpSource, """
    <FRR>func <FICTM>minMax<FRRCTM>(<FIRCTM>array<FCTM>: <FRCTM>[<FICTM>Int<FCTM>]<FEECTM>)<E> <FR>-> <FRCTM>(<FIRRCTM>min<FCTM>: <FICTM>Int<FCTM>,<E> <FIRCTM>max<FCTM>: <FICTM>Int<FEECTM>)<EEECTM> <FR>{
        <FRR>var <FIRCTM>currentMin<CTM> <FR>= <FIRCTM>array<FCTM>[<FCTM>0<FCTM>]<EEEECTM>
        <FR>var <FIRCTM>currentMax<CTM> <FR>= <FIRCTM>array<FCTM>[<FCTM>0<FCTM>]<EEEECTM>
        <FR>for <FICTM>value<CTM> <F>in <FIRCTM>array<FCTM>[<FRCTM>1<FCTM>..<<FIRCTM>array<FCTM>.<FICTM>count<FEECTM>]<ECTM> <FR>{
            <FRCTM>if <FIRCTM>value<CTM> <F>< <FICTM>currentMin<ECTM> <FR>{
                <FIRCTM>currentMin<CTM> <F>= <FICTM>value<ECTM>
            <F>}<E> <F>else <FRCTM>if <FIRCTM>value<CTM> <F>> <FICTM>currentMax<ECTM> <FR>{
                <FIRCTM>currentMax<CTM> <F>= <FICTM>value<ECTM>
            <F>}<EEECTM>
        <F>}<EE>
        <FR>return <FRCTM>(<FIRRCTM>currentMin<FCTM>,<E> <FICTM>currentMax<FECTM>)<EEECTM>
    <F>}<EE>

    <FR>let <FIRCTM>result<CTM> <FR>= <FIRCTM>minMax<FCTM>(<FIRCTM>array<FCTM>: <FRCTM>[<FRRCTM>10<FCTM>,<E> <FRCTM>43<FCTM>,<E> <FRCTM>1<FCTM>,<E> <FCTM>2018<FECTM>]<FEECTM>)<EEEECTM>
    <FIRCTM>print<FCTM>(<FRCTM>\"<FR>range: <FR>\\<F>(<FIRCTM>result<FCTM>.<FICTM>min<FECTM>)<FE> – <FR>\\<F>(<FIRCTM>result<FCTM>.<FICTM>max<FECTM>)<FFEE>\"<FECTM>)<FEECTM>
    """)
  }

  func testCompletionExpectedResults() {
    typealias TestCase = (line: UInt, source: String, expected: [String])
    let cases: [TestCase] = [
      (#line, "foo(x: 10)", ["call:foo(x:)"]),
      (#line, "foo(45)", ["call:foo(_:)"]),
      (#line, "foo.bar(first, x: 10)", ["foo", "call:bar(_:x:)", "first", "x:"]),
      (#line, "foo.bar(x:_:)", ["foo", "bar(x:_:)"]),

      // FIXME: code completion doesn't complete compound name references
      (#line, ".foo(x:y:z:)", ["foo(x:y:z:)"/*, "x", "y", "z"*/]),
      (#line, ".foo(1, 2, other: 5)", ["call:foo(_:_:other:)", "other:"]),
      (#line, "Foo.foo(fooInstance)(x: 10)", ["Foo", "call:foo(x:)", "fooInstance"]),

      // The below foo could be either foo(_:) or foo(_:_:), we can't tell
      // syntactically so default to the outer argument list, as it will match
      // even if it should have been the inner argument list due to the
      // incomplete information the matching logic has (it has to assume any
      // parameter could be defaulted or variadic).
      (#line, "Foo.foo(fooInstance)(10, 20)", ["Foo", "call:foo(_:_:)", "fooInstance"]),
      (#line, "Foo.foo(fooInstance)()", ["Foo", "call:foo", "fooInstance"]),
      (#line, "let (x, y) = (a, b)", ["a", "b"]),
      (#line, "if case let .myCase(Int.max, second) = p {}", ["patt:myCase(_:_:)", "Int", "max", "p"]),
      (#line, "if case let .myCase(.inner(x:foo), second) = p {}", ["patt:myCase(_:_:)", "patt:inner(x:)", "p"]),
      (#line, "switch x { case .some(2?): break }", ["x", "patt:some(_:)"]),

      // TODO: we don't check operators at the moment
      (#line, "3 + 4", []),
      // FIXME: code completion doesn't offer labels after break/continue
      (#line, "foo: for x in 1...4 { print(x); break foo }", ["call:print(_:)", "x"/*, "foo"*/]),

      // TODO: subscript completions after [
      (#line, "data[position]", ["data", "position"]),
      (#line, "data[position, default: 0]", ["data", "position", "default:"]),

      // FIXME: completion doesn't suggest anonymous closure params (e.g. $0)
      (#line, "$0.first", [/*"$0",*/ "first"]),
      (#line, "[1,2,4].filter{ $0 == 4 }", ["call:filter"/*, "$0"*/])
    ]

    for test in cases {
      let generated = RequestActionGenerator().generate(for: test.source)
        .compactMap { action -> String? in
          if case .codeComplete(_, let expected) = action, expected != nil {
            let type: String
            switch expected!.kind {
            case .call:
              type = "call:"
            case .pattern:
              type = "patt:"
            case .reference:
              type = ""
            }
            return "\(type)\(expected!.name.name)"
          }
          return nil
        }
      XCTAssertEqual(generated, test.expected, line: test.line)
    }
  }

  func testExpectedResultMatcher() {
    typealias TestCase = (match: ExpectedResult.Kind, of: String, against: String, ignoreArgs: Bool, result: Bool)
    let cases: [TestCase] = [
      (match: .reference, of: "myVar", against: "myVar", ignoreArgs: false, result: true),
      (match: .reference, of: "myVar", against: "MyVar", ignoreArgs: true, result: false),
      (match: .reference, of: "MyType", against: "MyType", ignoreArgs: true, result: true),
      (match: .reference, of: "MyType", against: "myType", ignoreArgs: true, result: false),
      (match: .reference, of: "myLabel:", against: "myLabel:", ignoreArgs: false, result: true),
      (match: .reference, of: "myLabel:", against: "myLabel", ignoreArgs: false, result: false),
      (match: .reference, of: "myLabel", against: "myLabel:", ignoreArgs: false, result: false),
      // C functions don't have any '_' labels in 'against' even if they take arguments.
      (match: .call, of: "bar(_:)", against: "bar()", ignoreArgs: false, result: true),
      (match: .call, of: "bar()", against: "bar(_:)", ignoreArgs: false, result: true),
      (match: .call, of: "bar(_:)", against: "bar(y:)", ignoreArgs: false, result: false),
      (match: .call, of: "bar(y:)", against: "bar(y:)", ignoreArgs: false, result: true),
      (match: .call, of: "bar(y:)", against: "bar(x:_:y:)", ignoreArgs: false, result: true),
      (match: .call, of: "bar(_:_:_:y:)", against: "bar(x:_:y:)", ignoreArgs: false, result: true),
      (match: .call, of: "bar(z:)", against: "bar(x:_:y:)", ignoreArgs: false, result: false),
      (match: .call, of: "bar(x:)", against: "bar(x:_:y:)", ignoreArgs: false, result: true),
      (match: .call, of: "myFuncTypeVar(_:_:)", against: "myFuncTypeVar", ignoreArgs: true, result: true),
      (match: .call, of: "myFuncTypeVar(_:_:)", against: "myFuncTypeVar", ignoreArgs: false, result: false),
      (match: .reference, of: "bar(y:)", against: "bar(y:)", ignoreArgs: false, result: true),
      (match: .reference, of: "bar(y:)", against: "bar(x:_:y:)", ignoreArgs: false, result: false),
      (match: .reference, of: "bar", against: "bar(x:_:y:)", ignoreArgs: false, result: true),
      (match: .reference, of: "Foo(x:)", against: "Foo", ignoreArgs: false, result: false),
      (match: .call, of: "Foo(x:)", against: "Foo", ignoreArgs: true, result: true),
      (match: .call, of: "Foo(x:)", against: "Foo", ignoreArgs: false, result: false),
      (match: .pattern, of: "first(_:)", against: "first(x:y:)", ignoreArgs: false, result: true),
      (match: .pattern, of: "first", against: "first(x:y:)", ignoreArgs: false, result: true),
      (match: .pattern, of: "first(_:z:)", against: "first(x:y:)", ignoreArgs: false, result: false),
      (match: .pattern, of: "first(_:)", against: "first", ignoreArgs: false, result: false),
      (match: .pattern, of: "first(_:)", against: "first()", ignoreArgs: false, result: true),
      (match: .pattern, of: "first(_:_:)", against: "first()", ignoreArgs: false, result: true)
    ]

    for test in cases {
      let matcher = CompletionMatcher(for: ExpectedResult(name: SwiftName(test.of)!, kind: test.match))
      XCTAssertEqual(matcher.match(test.against, ignoreArgLabels: test.ignoreArgs), test.result, "comparing \(test.match.rawValue) of \(test.of) against \(test.against) \(test.ignoreArgs ? "ex" : "in")cluding args does not return \(test.result)")
    }
  }

  func testRewriteActionGenerator() {
    let actions = BasicRewriteActionGenerator().generate(for: testFile)
    verify(actions, rewriteMode: .basic, expectedActionTypes: ALL_ACTIONS)
  }

  func testTypoRewriteActionGenerator() {
    let actions = TypoActionGenerator().generate(for: testFile)
    let expectedActions = ALL_ACTIONS.filter({ $0 != .rangeInfo && $0 != .collectExpressionType})
    verify(actions, rewriteMode: .typoed, expectedActionTypes: expectedActions)
  }

  func testConcurrentRewriteActionGenerator() {
    let actions = ConcurrentRewriteActionGenerator().generate(for: testFile)
    verify(actions, rewriteMode: .concurrent, expectedActionTypes: ALL_ACTIONS)
  }

  func testInsideOutActionGenerator() {
    let actions = InsideOutRewriteActionGenerator().generate(for: testFile)
    verify(actions, rewriteMode: .insideOut, expectedActionTypes: ALL_ACTIONS)

    let edits = InsideOutRewriteActionGenerator().generate(for: "a.b([.c])").filter {
        guard case .replaceText = $0 else { return false }
        return true
    }
    XCTAssertEqual(edits, [
        Action.replaceText(offset: 0, length: 9, text: ""),
        Action.replaceText(offset: 0, length: 0, text: "."), // .
        Action.replaceText(offset: 1, length: 0, text: "c"), // .c
        Action.replaceText(offset: 0, length: 0, text: "["), // [.c
        Action.replaceText(offset: 3, length: 0, text: "]"), // [.c]
        Action.replaceText(offset: 0, length: 0, text: "a"), // a[.c]
        Action.replaceText(offset: 1, length: 0, text: "."), // a.[.c]
        Action.replaceText(offset: 2, length: 0, text: "b"), // a.b[.c]
        Action.replaceText(offset: 3, length: 0, text: "("), // a.b([.c]
        Action.replaceText(offset: 8, length: 0, text: ")"), // a.b([.c])
    ])
  }

  func verify(_ actions: [Action], rewriteMode: RewriteMode, expectedActionTypes: [Action.BaseAction]) {
    var state = SourceState(rewriteMode: rewriteMode, content: testFileContent)

    for action in actions {
      let eof = state.source.utf8.count
      switch action {
      case .cursorInfo(let offset):
        XCTAssertTrue(offset >= 0 && offset <= eof)
      case .codeComplete(let offset, _), .conformingMethodList(let offset), .typeContextInfo(let offset):
        XCTAssertTrue(offset >= 0 && offset <= eof)
      case .rangeInfo(let offset, let length):
        XCTAssertTrue(offset >= 0 && offset <= eof)
        XCTAssertTrue(length > 0 && offset + length <= eof)
      case .replaceText(let offset, let length, let text):
        XCTAssertTrue(offset >= 0 && offset <= eof)
        XCTAssertTrue(length >= 0 && offset + length <= eof)
        state.replace(offset: offset, length: length, with: text)
      case .collectExpressionType:
        break
      case .format(let offset):
        XCTAssertTrue(offset >= 0 && offset <= eof)
      case .testModule:
        break;
      }
    }
    XCTAssertEqual(state.source, testFileContent)

    let grouped = Dictionary(grouping: actions, by: { action -> Action.BaseAction in
      switch action {
      case .cursorInfo:
        return .cursorInfo
      case .codeComplete:
        return .codeComplete
      case .rangeInfo:
        return .rangeInfo
      case .replaceText:
        return .replaceText
      case .typeContextInfo:
        return .typeContextInfo
      case .conformingMethodList:
        return .conformingMethodList
      case .collectExpressionType:
        return .collectExpressionType
      case .format:
        return .format
      case .testModule:
        return .testModule
      }
    })

    XCTAssertEqual(grouped.keys.count, expectedActionTypes.count)
    for key in expectedActionTypes {
      XCTAssert(grouped.keys.contains(key), "\(key) not found")
    }
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

  override func tearDown() {
    super.tearDown()
    try? FileManager.default.removeItem(at: workspace)
  }
}

final class ActionMarkup {
  let source: String
  let actions: [Action]

  init(_ actions: [Action], in source: String) {
    self.source = source
    self.actions = actions
  }

  var markedUpSource: String {
    var result = ""
    let insertions = actions
      .flatMap { action -> [(Int, String)] in
        switch action {
        case .cursorInfo(let offset):
          return [(offset, "I")]
        case .codeComplete(let offset, _):
          return [(offset, "C")]
        case .rangeInfo(let offset, let length):
          return [(offset, "R"), (offset + length, "E")]
        case .replaceText:
          preconditionFailure("actions do not modify the source")
        case .typeContextInfo(let offset):
          return [(offset, "T")]
        case .conformingMethodList(let offset):
          return [(offset, "M")]
        case .collectExpressionType:
          return [] // no associated location
        case .format(let offset):
          return [(offset, "F")]
        case .testModule:
          return []
        }
      }
      .enumerated()
      .sorted { a, b in
        if a.element.0 < b.element.0 { return true }
        return a.offset < b.offset
      }
      .map { $1 }
      .divide { offset, _ in  offset }
      .map { ($0.first!.0, $0.map{ $1 }.reduce("", +)) }

    var lastIndex = source.utf8.startIndex
    for (offset, label) in insertions {
      let index = source.utf8.index(source.utf8.startIndex, offsetBy: offset)
      if index != lastIndex {
        result += String(source.utf8[lastIndex..<index])!
      }
      result += "<\(label)>"
      lastIndex = index
    }
    if lastIndex != source.utf8.endIndex {
      result += String(source.utf8[lastIndex...])!
    }
    return result
  }
}
