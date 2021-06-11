//===--------------------- SourceKitdClient.swift -------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
// This file provides a wrapper of SourceKitd service.
//===----------------------------------------------------------------------===//

import sourcekitd
import Dispatch

/// An empty object to generate unique `ObjectIdentifier`s.
fileprivate class Object {}

public class SourceKitdService {

  enum State {
    case running
    case interrupted
    case semaDisabled
  }

  /// The queue that makes sure only one request is executed at a time
  private let requestQueue = DispatchQueue(label: "SourceKitdService.requestQueue", qos: .userInitiated)

  /// The queue that guards access to the `state` and `stateChangeHandlers` variables
  private let stateQueue = DispatchQueue(label: "SourceKitdService.stateQueue", qos: .userInitiated)

  private var state: State = .running {
    didSet {
      dispatchPrecondition(condition: .onQueue(stateQueue))
      for handler in stateChangeHandlers.values {
        handler()
      }
    }
  }

  /// Handlers to be executed whenever the `state` changes.
  private var stateChangeHandlers: [ObjectIdentifier: () -> Void] = [:]

  public init() {
    initializeService()
  }

  /// Set up a new SourceKit service instance.
  private func initializeService() {
    sourcekitd_initialize()
    sourcekitd_set_notification_handler { [self] resp in
      let response = SourceKitdResponse(resp: resp!)

      stateQueue.async {
        if self.state == .interrupted {
          self.state = .semaDisabled

          // sourcekitd came back online. Poke it to restore semantic
          // functionality. Intentionally don't execute this request on the
          // request queue because request order doesn't matter for this
          // pseudo-document and we want it to be executed immediately, even if
          // the request queue is blocked.
          let request = SourceKitdRequest(uid: .request_CursorInfo)
          request.addParameter(.key_SourceText, value: "")
          _ = sourcekitd_send_request_sync(request.rawRequest)
        }

        if response.isConnectionInterruptionError {
          self.state = .interrupted
        } else if response.notificationType == .semaDisabledNotification {
          self.state = .semaDisabled
        } else if response.notificationType == .semaEnabledNotification {
          self.state = .running
        }
      }
    }
  }

  deinit {
    sourcekitd_shutdown()
  }

  /// Restarts the service. This is a workaround to set up a new service in case
  /// we time out waiting for a request response and we want to handle it.
  /// Replace by proper cancellation once we have cancellation support in
  /// SourceKit.
  public func restart() {
    sourcekitd_shutdown()
    // We need to wait for the old service to fully shut down before we can
    // create a new one but we don't receive a notification when the old service
    // did shut down. Waiting for a second seems to give it enough time.
    sleep(1)
    initializeService()
    stateQueue.sync {
      self.state = .running
    }
  }

  /// Execute `callback` one this service is in `desiredState`
  private func waitForState(_ desiredState: State, callback: @escaping () -> Void) {
    stateQueue.async { [self] in
      if state == desiredState {
        callback()
      } else {
        let identifier = ObjectIdentifier(Object())
        stateChangeHandlers[identifier] = { [self] in
          dispatchPrecondition(condition: .onQueue(stateQueue))
          if state == desiredState {
            callback()
            stateChangeHandlers[identifier] = nil
          }
        }
      }
    }
  }

  /// Block the current thread until this service is in `desiredState`.
  private func blockUntilState(_ desiredState: State) {
    let semaphore = DispatchSemaphore(value: 0)
    waitForState(desiredState) {
      semaphore.signal()
    }
    semaphore.wait()
  }

  /// Send a request synchronously with a handler for its response.
  /// - Parameter request: The request to send.
  /// - Returns: The response from the sourcekitd service.
  public func sendSyn(request: SourceKitdRequest) -> SourceKitdResponse {
    return requestQueue.sync {
      blockUntilState(.running)
      return SourceKitdResponse(resp: sourcekitd_send_request_sync(request.rawRequest))
    }
  }

  /// Send a request asynchronously with a handler for its response.
  /// - Parameter request: The request to send.
  /// - Parameter handler: The handler for the response in the future.
  public func send(request: SourceKitdRequest,
                   handler: @escaping (SourceKitdResponse) -> ())  {
    requestQueue.async { [self] in
      blockUntilState(.running)
      let response = SourceKitdResponse(resp: sourcekitd_send_request_sync(request.rawRequest))
      if response.isConnectionInterruptionError {
        // Set the state into the interrupted state now. We will also catch this
        // in the notification handler but that has some delay and we might be
        // scheduling new requests before the state is set to `interrupted`.
        stateQueue.sync {
          self.state = .interrupted
        }
      }
      handler(response)
    }
  }
}
