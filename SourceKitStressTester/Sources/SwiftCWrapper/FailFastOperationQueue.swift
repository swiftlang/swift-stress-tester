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

public final class FailFastOperationQueue<Item: Operation> {
  private let serialQueue = DispatchQueue(label: "\(FailFastOperationQueue.self)")
  private let queue = OperationQueue()
  private let operations: [Item]
  private let completionHandler: (Item, Int, Int) -> Bool

  init(operations: [Item], maxWorkers: Int = ProcessInfo.processInfo.activeProcessorCount,
       completionHandler: @escaping (Item, Int, Int) -> Bool) {
    self.operations = operations
    self.completionHandler = completionHandler
    queue.maxConcurrentOperationCount = maxWorkers
  }

  func waitUntilFinished() {
    let group = DispatchGroup()
    var completed = 0

    for (index, operation) in operations.enumerated() {
      group.enter()
      operation.completionBlock = { [weak self, weak operation] in
        defer { group.leave() }
        guard let `self` = self, let operation = operation else { return }

        self.serialQueue.sync {
          completed += 1
          if !self.completionHandler(operation, completed, self.operations.count) {
            self.cancelAfter(index)
          }
        }
      }
      queue.addOperation(operation)
    }
    queue.waitUntilAllOperationsAreFinished()
    group.wait()
  }

  private func cancelAfter(_ index: Int) {
    let nextIndex = index.advanced(by: 1)
    if nextIndex < self.operations.endIndex {
      self.operations[nextIndex...].forEach { $0.cancel() }
    }
  }
}
