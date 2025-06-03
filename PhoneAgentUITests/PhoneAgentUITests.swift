//
//  PhoneAgentUITests.swift
//  PhoneAgentUITests
//
//  Created by Rounak Jain on 5/30/25.
//

import XCTest

final class PhoneAgent: XCTestCase {
    let appListener = AppStreamListener()
    var task: Task<Void, Never>?

    var api: GeminiService?
    let notificationCenter = UNUserNotificationCenter.current()
    var lastRequest: GeminiRequest?
    var app: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = true
        appListener.start()
        let app = XCUIApplication()
        app.launch()
        notificationCenter.requestNotificationPermission()

        notificationCenter.delegate = self
    }

    @MainActor
    func testLoop() async throws {
        for await prompt in appListener.messages {
            switch prompt {
            case .apiKey(let apiKey):
                api = GeminiService(with: apiKey)
            case .prompt(let prompt):
                guard task == nil || task?.isCancelled == false else { continue }
                task = Task {
                    do {
                        try await submit(prompt)
                    } catch {
                        print("Error processing prompt: \(error)")
                    }
                }
            }
        }
    }


    func testDecoding() throws {
        let rawResponse =
        """
        {
          "id": "resp_683b49b0916c819b9db77fc68c0ed429016e90871fbf8114",
          "object": "response",
          "created_at": 1748715952,
          "status": "completed",
          "background": false,
          "error": null,
          "incomplete_details": null,
          "instructions": null,
          "max_output_tokens": null,
          "model": "gpt-4.1-2025-04-14",
          "output": [
            {
              "id": "fc_683b49b19d00819bbb0c6ca4ab088c85016e90871fbf8114",
              "type": "function_call",
              "status": "completed",
              "arguments": "{\\\"bundle_identifier\\\":\\\"com.apple.Preferences\\\"}",
              "call_id": "call_VduQZcKYvlyfrY5SINGzVrTd",
              "name": "openApp"
            },
            {
              "id": "fc_683b49b636f4819ba3b969b0b0085edf016e90871fbf8114",
              "type": "function_call",
              "status": "completed",
              "arguments": "{}",
              "call_id": "call_BvRXpELYGUyPqoQbyVnB69xC",
              "name": "fetchAccessibilityTree"
            },
            {
              "id": "msg_683b5224ecb8819baa03843bc12f514603d927c115159226",
              "type": "message",
              "status": "completed",
              "content": [
                {
                  "type": "output_text",
                  "annotations": [],
                  "text": "Settings is now open. What would you like to do next? (For example: adjust Wi-Fi, Bluetooth, display, notifications, etc.)"
                }
              ],
              "role": "assistant"
            }
          ],
          "previous_response_id": "resp_683b49b0916c819b9db77fc68c0ed429016e90871fbf8114",
        }
        """
        let response = try JSONDecoder.shared.decode(GeminiResponse.self, from: .init(rawResponse.utf8))
        XCTAssertEqual(
            response,
            GeminiResponse(
                id: "resp_683b49b0916c819b9db77fc68c0ed429016e90871fbf8114",
                output: [.functionCall(
                            id:  "call_VduQZcKYvlyfrY5SINGzVrTd",
                            .openApp(
                                bundleIdentifier: "com.apple.Preferences"
                            )
                        ),
                         .functionCall(
                            id: "call_BvRXpELYGUyPqoQbyVnB69xC",
                            .fetchAccessibilityTree
                         ),
                         .message(.init(content: [
                            .init(type: .outputText, text: "Settings is now open. What would you like to do next? (For example: adjust Wi-Fi, Bluetooth, display, notifications, etc.)")
                         ]))]
            )
        )
    }
}

extension UNUserNotificationCenter {
    func requestNotificationPermission() {
        requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Request authorization failed: \(error.localizedDescription)")
            }

            if granted {
                print("Notification permission granted.")
            } else {
                print("Notification permission denied.")
            }
        }
    }
}
