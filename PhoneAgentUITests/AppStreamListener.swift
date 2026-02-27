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
    private let listenerQueue = DispatchQueue(label: "PhoneAgent.AppStreamListener")
    private var connections: [NWConnection] = []
    private var receiveBuffers: [ObjectIdentifier: Data] = [:]
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

        listener.newConnectionHandler = { [weak self] newConnection in
            guard let self else { return }
            self.connections.append(newConnection)
            self.receiveBuffers[ObjectIdentifier(newConnection)] = Data()
            newConnection.start(queue: self.listenerQueue)
            self.setupReceive(on: newConnection)
            print("Server accepted connection from \(String(describing: newConnection.endpoint))")
        }

        listener.start(queue: listenerQueue)
    }

    let decoder = JSONDecoder()

    private func setupReceive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            let connectionID = ObjectIdentifier(connection)

            if let data, !data.isEmpty {
                self.consumeBufferedMessages(data, for: connectionID)
            }

            if isComplete {
                self.cleanupConnection(connection, id: connectionID)
            } else if let error = error {
                print("Server error: \(error)")
                self.cleanupConnection(connection, id: connectionID)
            } else {
                self.setupReceive(on: connection)
            }
        }
    }

    private func consumeBufferedMessages(_ incomingData: Data, for connectionID: ObjectIdentifier) {
        var buffer = receiveBuffers[connectionID, default: Data()]
        buffer.append(incomingData)

        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let packet = Data(buffer[..<newlineIndex])
            buffer.removeSubrange(...newlineIndex)
            guard !packet.isEmpty else { continue }
            guard let message = try? decoder.decode(AppToTestMessage.self, from: packet) else {
                print("Failed to decode AppToTestMessage packet")
                continue
            }
            continuation.yield(message)
        }

        receiveBuffers[connectionID] = buffer
    }

    private func cleanupConnection(_ connection: NWConnection, id: ObjectIdentifier) {
        connection.cancel()
        receiveBuffers.removeValue(forKey: id)
        connections.removeAll { $0 === connection }
    }
}
