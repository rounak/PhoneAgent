//
//  AppStreamListener.swift
//  PhoneAgent
//
//  Created by Rounak Jain on 5/31/25.
//

import Network
import Foundation
import XCTest

public enum AppToTestMessage: Codable {
    case prompt(String)
    case apiKey(String)
}

class AppStreamListener {
    typealias AsyncMessageStream = AsyncStream<AppToTestMessage>
    private let listener: NWListener
    private var connections: [NWConnection] = []
    public let messages: AsyncMessageStream
    private let continuation: AsyncMessageStream.Continuation
    private let port: NWEndpoint.Port = 12345

    init() {
        do {
            var tempContinuation: AsyncMessageStream.Continuation!
            self.messages = AsyncStream { continuation in
                tempContinuation = continuation
            }
            self.continuation = tempContinuation
            listener = try NWListener(using: .tcp, on: port)
        } catch {
            fatalError("Failed to create listener: \(error)")
        }
    }

    func start() {
        listener.stateUpdateHandler = { newState in
            print("Server state: \(newState)")
        }

        listener.newConnectionHandler = { [weak self] (newConnection) in
            self?.connections.append(newConnection)
            self?.setupReceive(on: newConnection)
            newConnection.start(queue: .main)
            print("Server accepted connection from \(String(describing: newConnection.endpoint))")
        }

        listener.start(queue: .main)
    }

    let decoder = JSONDecoder()

    private func setupReceive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (data, _, isComplete, error) in
            if let data, !data.isEmpty, let message = try? self?.decoder.decode(AppToTestMessage.self, from: data) {
                // Publish the message via async sequence
                self?.continuation.yield(message)
            }
            if isComplete {
                connection.cancel()
                self?.continuation.finish()
                self?.connections.removeAll { $0 === connection }
            } else if let error = error {
                print("Server error: \(error)")
                connection.cancel()
                self?.continuation.finish()
                self?.connections.removeAll { $0 === connection }
            } else {
                self?.setupReceive(on: connection)
            }
        }
    }
}
