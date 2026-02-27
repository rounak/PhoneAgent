//
//  AppToTestStream.swift
//  PhoneAgent
//
//  Created by Rounak Jain on 5/31/25.
//

import Foundation
import Network

public enum AppToTestMessage: Codable {
    case prompt(String)
    case apiKey(String)
}

class AppToTestStream {

    private let host: NWEndpoint.Host = .ipv4(IPv4Address.loopback)
    private let port: NWEndpoint.Port = 12345
    private let queue = DispatchQueue(label: "PhoneAgent.AppToTestStream")
    private var connection: NWConnection?
    private var isReady = false
    private var isSending = false
    private var pendingMessages: [Data] = []
    private var reconnectWorkItem: DispatchWorkItem?
    private let reconnectDelay: TimeInterval = 0.5

    init() {
        // Defer connection setup until connect() so listeners can come online first.
    }

    func connect() {
        queue.async { [weak self] in
            self?.ensureConnection()
        }
    }

    let encoder = JSONEncoder()

    func send(message: AppToTestMessage) {
        do {
            var data = try encoder.encode(message)
            // Delimit messages since TCP packets do not preserve send() boundaries.
            data.append(0x0A)
            queue.async { [weak self] in
                guard let self else { return }
                self.pendingMessages.append(data)
                self.ensureConnection()
                self.flushPendingMessages()
            }
        } catch {
            print("Failed to encode message: \(error)")
            return
        }
    }

    private func ensureConnection() {
        guard connection == nil else { return }
        let connection = NWConnection(host: host, port: port, using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            self?.queue.async {
                self?.handleStateUpdate(state)
            }
        }
        connection.start(queue: queue)
    }

    private func handleStateUpdate(_ state: NWConnection.State) {
        print("Client state: \(state)")
        switch state {
        case .ready:
            reconnectWorkItem?.cancel()
            reconnectWorkItem = nil
            isReady = true
            flushPendingMessages()
        case .waiting(let error):
            print("Client waiting for connection: \(error)")
            isReady = false
            scheduleReconnect()
        case .failed(let error):
            print("Client connection failed: \(error)")
            resetConnection()
            scheduleReconnect()
        case .cancelled:
            resetConnection()
            scheduleReconnect()
        case .setup, .preparing:
            break
        @unknown default:
            isReady = false
        }
    }

    private func flushPendingMessages() {
        guard isReady, !isSending, !pendingMessages.isEmpty, let connection else { return }
        isSending = true
        let packet = pendingMessages[0]
        connection.send(content: packet, completion: .contentProcessed({ [weak self] error in
            guard let self else { return }
            self.queue.async {
                self.isSending = false
                if let error {
                    print("Client failed to send data: \(error)")
                    self.resetConnection()
                    self.scheduleReconnect()
                } else {
                    print("Client sent data")
                    self.pendingMessages.removeFirst()
                    self.flushPendingMessages()
                }
            }
        }))
    }

    private func resetConnection() {
        isReady = false
        isSending = false
        connection?.cancel()
        connection = nil
    }

    private func scheduleReconnect() {
        guard reconnectWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reconnectWorkItem = nil
            self.ensureConnection()
        }
        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + reconnectDelay, execute: workItem)
    }
}
