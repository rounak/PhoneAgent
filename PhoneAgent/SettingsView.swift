//
//  SettingsView.swift
//  PhoneAgent
//
//  Created by Rounak Jain on 5/31/25.
//

import SwiftUI

enum Constants {
    static let defaultWakeWord = "Agent"
}

struct SettingsView: View {
    @AppStorage("alwaysOn") private var alwaysOn = false
    @AppStorage("wakeWord") private var wakeWord = ""
    let deleteKey: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Always on", isOn: $alwaysOn)
                if alwaysOn {
                    HStack {
                        Text("Set Custom Wake Word")
                        TextField(Constants.defaultWakeWord, text: $wakeWord)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                    }
                }
                Text("Trigger prompts while the app is backgrounded. Microphone will stay active.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            Section {
                Button(role: .destructive) {
                    deleteKey()
                } label: {
                    Text("Delete API Key")
                }
            }
        }
    }
}

#Preview {
    SettingsView(deleteKey: {})
}
