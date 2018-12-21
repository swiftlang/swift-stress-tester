// SwiftEvolveKit/IO.swift - Logging to stderr
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
// -----------------------------------------------------------------------------
///
/// This file implements a log() function which can be used to write to stderr.
///
// -----------------------------------------------------------------------------

import Foundation

public func log(_ items: Any..., separator: String = " ", terminator: String = "\n") {
  var stderr = FileHandle.standardError
  print(items.map(String.init(describing:)).joined(separator: separator),
        terminator: terminator, to: &stderr)
}

extension FileHandle: TextOutputStream {
  public func write(_ string: String) {
    self.write(string.data(using: .utf8)!)
  }
}

public func withErrorContext<Result>(
  url: URL?, debugDescription: String, do body: () throws -> Result
) throws -> Result {
  do {
    return try body()
  }
  catch let error as NSError {
    var userInfoCopy = error.userInfo
    
    userInfoCopy[NSURLErrorKey] = url
    userInfoCopy[NSDebugDescriptionErrorKey] = debugDescription
    
    throw NSError(domain: error.domain, code: error.code, userInfo: userInfoCopy)
  }
  catch {
    assertionFailure("Non-NSError: \(error)")
    throw error
  }
}

