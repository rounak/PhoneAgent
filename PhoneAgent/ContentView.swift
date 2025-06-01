//
//  ContentView.swift
//  PhoneAgent
//
//  Created by Rounak Jain on 5/30/25.
//

import SwiftUI
import Security

struct ContentView: View {
    enum AppState {
        case enterAPIKey
        case prompt(String)
    }

    @State private var state: AppState = KeychainHelper.load().map { .prompt($0) } ?? .enterAPIKey
    let appToTestStream: AppToTestStream

    var body: some View {
        switch state {
        case .enterAPIKey:
            EnterAPIKeyView { key in
                KeychainHelper.save(key: key)
                state = .prompt(key)
            }
        case .prompt(let key):
            PromptView(appToTestStream: appToTestStream, deleteKey: deleteKey)
                .onAppear {
                    appToTestStream.send(message: .apiKey(key))
                }
        }
    }

    private func deleteKey() {
        KeychainHelper.delete()
        state = .enterAPIKey
    }
}


