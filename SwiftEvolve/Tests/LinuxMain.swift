import XCTest

import SwiftEvolveTests
import SwiftEvolveKitTests

var tests = [XCTestCaseEntry]()
tests += SwiftEvolveTests.allTests()
tests += SwiftEvolveKitTests.allTests()
XCTMain(tests)
