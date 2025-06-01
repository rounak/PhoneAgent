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

    private var connection: NWConnection
    private var port: NWEndpoint.Port

    init() {
        self.port = 12345
        self.connection = NWConnection(host: .ipv4(IPv4Address.loopback), port: self.port, using: .tcp)
    }

    func connect() {
        connection.stateUpdateHandler = { state in
            print("Client state: \(state)")
        }
        connection.start(queue: .main)
    }

    let encoder = JSONEncoder()

    func send(message: AppToTestMessage) {
        do {
            let data = try encoder.encode(message)
            connection.send(content: data, completion: .contentProcessed({ error in
                if let error {
                    print("Client failed to send data: \(error)")
                } else {
                    print("Client sent data")
                }
            }))
        } catch {
            print("Failed to encode message: \(error)")
            return
        }
    }
}
