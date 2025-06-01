//
//  PhoneAgentApp.swift
//  PhoneAgent
//
//  Created by Rounak Jain on 5/30/25.
//

import SwiftUI

@main
struct PhoneAgentApp: App {
    let appToTestStream = AppToTestStream()
    var body: some Scene {
        WindowGroup {
            ContentView(appToTestStream: appToTestStream)
                .onAppear {
                    appToTestStream.connect()
                }
        }
    }
}
