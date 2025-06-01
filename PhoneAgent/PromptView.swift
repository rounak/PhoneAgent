//
//  PromptView.swift
//  PhoneAgent
//
//  Created by Rounak Jain on 5/31/25.
//

import SwiftUI

struct PromptView: View {
    @State var textFieldText = ""
    @State var largeText = ""
    @State private var speechProcessor = SpeechProcessor()
    let appToTestStream: AppToTestStream
    @State private var showingSettings = false
    let deleteKey: () -> Void
    @AppStorage("alwaysOn") private var alwaysOn = false
    @AppStorage("wakeWord") private var wakeWord = ""

    var body: some View {
        NavigationStack {
            VStack {
                Text(largeText)
                    .font(.largeTitle)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.1), value: largeText)

                Spacer()
                MicrophoneButton(recording: $speechProcessor.isRecording, start: {
                    speechProcessor.start()
                }, stop: {
                    speechProcessor.stopAndQuery()
                })
                Spacer()
                TextField("Enter your query", text: $textFieldText)
                    .multilineTextAlignment(.center)
                    .onSubmit {
                        keyboardQuery()
                    }
            }
            .onChange(of: speechProcessor.transcript, { _, newValue in
                largeText = newValue
            })
            .task {
                for await text in speechProcessor.utterances {
                    largeText = text
                    query(with: text)
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(deleteKey: deleteKey)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    func keyboardQuery() {
        largeText = textFieldText
        query(with: textFieldText)
        textFieldText = ""
    }

    func query(with text: String) {
        print("query: \(text)")
        let wakeWord = (wakeWord.isEmpty ? Constants.defaultWakeWord : wakeWord).lowercased()
        let hasWakeWord = text.prefix(wakeWord.count).lowercased().hasPrefix(wakeWord) && alwaysOn
        guard hasWakeWord || UIApplication.shared.applicationState == .active else { return }
        var q = text
        if hasWakeWord {
            q = String(text[text.index(text.startIndex, offsetBy: wakeWord.count)...])
        }
        appToTestStream.send(message: .prompt(q))
    }
}

struct MicrophoneButton: View {
    @Binding var recording: Bool
    let start: () -> Void
    let stop: () -> Void

    var body: some View {
        Button(action: {
            if recording {
                stop()
            } else {
                start()
            }
        }, label: {
            Image(systemName: recording ? "stop.circle.fill" : "mic.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
        })

    }
}

#Preview {
    PromptView(appToTestStream: .init(), deleteKey: {})
}
