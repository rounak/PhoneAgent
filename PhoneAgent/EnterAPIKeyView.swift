//
//  EnterAPIKeyView.swift
//  PhoneAgent
//
//  Created by Rounak Jain on 5/31/25.
//

import SwiftUI

struct EnterAPIKeyView: View {
    @State var apiKey: String = ""
    let onSave: (String) -> Void
    @State private var showKey: Bool = false
    @State private var saved: Bool = false
    let placeholder = "Enter your API key"
    @FocusState private var fieldFocused: Bool
    private var saveEnabled: Bool {
        !apiKey.isEmpty
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "key.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            VStack(spacing: 10) {
                Text("Enter your OpenAI API key")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Your key will be securely stored on your device.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            HStack {
                Group {
                    if showKey {
                        TextField(placeholder, text: $apiKey)
                    } else {
                        SecureField(placeholder, text: $apiKey)
                    }
                }
                .fontDesign(.monospaced)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($fieldFocused)

                Button {
                    if let clip = UIPasteboard.general.string {
                        apiKey = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showKey.toggle() }
                } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .frame(height: 48)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.separator, lineWidth: 1.0/UIScreen.main.scale)
            )

            Button(action: {
                fieldFocused = false            // dismiss keyboard
                onSave(apiKey)                  // let caller handle persistence
                withAnimation(.easeInOut) { saved = true }   // flash success banner
                Task {
                    try await Task.sleep(for: .seconds(1))
                    withAnimation(.easeInOut) { saved = false }
                }
            }) {
                Text("Save")
                    .frame(maxWidth: .infinity)          // make label stretch full‑width
                    .padding(.vertical, 10)
                    .foregroundStyle(saveEnabled ? .white : .secondary)
            }
            .background(!saveEnabled ? .gray.opacity(0.3) : .accentColor,
                        in: RoundedRectangle(cornerRadius: 12))
            .frame(height: 48)
            .contentShape(Rectangle())                    // tap anywhere in the rectangle
            .disabled(apiKey.isEmpty)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .overlay(alignment: .top) {
            if saved {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .onAppear { fieldFocused = true }
    }
}

struct KeychainHelper {
    private static let service = "PhoneAgentService"
    private static let account = "OpenAIAPIKey"

    static func save(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(key.utf8)
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }
}

#Preview {
    EnterAPIKeyView(apiKey: "", onSave: {_ in })
}
