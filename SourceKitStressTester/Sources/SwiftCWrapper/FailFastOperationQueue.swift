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
  private let completionHandler: (Int, Item, Int, Int) -> Bool

  public init(operations: [Item], maxWorkers: Int? = nil,
       completionHandler: @escaping (Int, Item, Int, Int) -> Bool) {
    self.operations = operations
    self.completionHandler = completionHandler
    let processorCount = ProcessInfo.processInfo.activeProcessorCount
    if let maxWorkers = maxWorkers, maxWorkers < processorCount {
      queue.maxConcurrentOperationCount = maxWorkers
    } else {
      queue.maxConcurrentOperationCount = processorCount
    }
  }

  public func waitUntilFinished() {
    let group = DispatchGroup()
    var completed = 0

    for (index, operation) in operations.enumerated() {
      group.enter()
      operation.completionBlock = { [weak self, weak operation] in
        defer { group.leave() }
        guard let `self` = self, let operation = operation else { return }

        self.serialQueue.sync {
          completed += 1
          if !self.completionHandler(index, operation, completed, self.operations.count) {
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
