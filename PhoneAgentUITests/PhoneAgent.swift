//
//  PhoneAgent.swift
//  PhoneAgent
//
//  Created by Rounak Jain on 5/31/25.
//

import Foundation
import XCTest

extension PhoneAgent {
    enum Error: Swift.Error, LocalizedError {
        case invalidTool(name: String?, message: String)
        case noAppFound
        case apiNotConfigured

        var errorDescription: String? {
            switch self {
            case .invalidTool(let name, let message):
                "Invalid tool \(name ?? "unknown"): \(message)"
            case .noAppFound:
                "No app found to interact with, try to open an app first."
            case .apiNotConfigured:
                "No API key found"
            }
        }
    }

    @MainActor
    func submit(_ prompt: String) async throws {
        try await recurse(with: GeminiRequest(with: prompt, accessibilityTree: app.map { $0.accessibilityTree() }))
    }

    @MainActor
    private func recurse(with request: GeminiRequest) async throws {
        guard let api else {
            throw Error.apiNotConfigured
        }

        // Make a mutable copy of the request to potentially add conversation history for recursion
        var currentRequest = request
        let response = try await api.send(currentRequest)

        // Process candidates from GeminiResponse
        guard let candidate = response.candidates?.first else {
            print("No candidates found in Gemini response.")
            // Consider sending a notification or handling this error appropriately
            return
        }

        guard let candidateContent = candidate.content else {
            print("No content found in Gemini candidate.")
            // Consider sending a notification or handling this error appropriately
            return
        }

        // It's important to update lastRequest with the request *before* it's modified for the next turn.
        // However, if the next turn is a function response, the conversation history needs to be preserved.
        // Let's update lastRequest to reflect the state that led to the current response.
        lastRequest = currentRequest

        for part in candidateContent.parts {
            if let text = part.text {
                print("Received text message: \(text)")
                // This is like the old .message case
                Task {
                    do {
                        try await sendNotification(message: text)
                    } catch {
                        print("Error sending notification: \(error)")
                    }
                }
                // Typically, if the model sends text, it's the end of this turn of interaction.
                // No immediate recursion with new data unless waiting for user reply (handled by handleQuickReply).
            } else if let functionCall = part.functionCall {
                print("Received function call: \(functionCall.name) with args: \(functionCall.args ?? [:])")
                let functionNameString = functionCall.name
                let args = functionCall.args ?? [:]
                var output: String

                do {
                    var declaredFunctionCall: GeminiDeclaredFunctionCall?
                    // Reconstruct GeminiDeclaredFunctionCall from functionCall.name and functionCall.args
                    if functionNameString == GeminiFunctionName.enterText.rawValue {
                        let coordinate = args["coordinate"] ?? ""
                        let textToEnter = args["text"] ?? ""
                        declaredFunctionCall = .enterText(coordinate: coordinate, text: textToEnter)
                    } else if functionNameString == GeminiFunctionName.fetchAccessibilityTree.rawValue {
                        declaredFunctionCall = .fetchAccessibilityTree
                    } else if functionNameString == GeminiFunctionName.openApp.rawValue {
                        let bundleIdentifier = args["bundle_identifier"] ?? ""
                        declaredFunctionCall = .openApp(bundleIdentifier: bundleIdentifier)
                    } else if functionNameString == GeminiFunctionName.tapElement.rawValue {
                        let coordinate = args["coordinate"] ?? ""
                        // Assuming count and longPress might be missing or need type conversion
                        let count = args["count"].flatMap { Int($0) }
                        let longPress = args["longPress"].flatMap { Bool($0) }
                        declaredFunctionCall = .tapElement(coordinate: coordinate, count: count, longPress: longPress)
                    } else if functionNameString == GeminiFunctionName.scroll.rawValue {
                        let x = args["x"].flatMap { Double($0) }.map { CGFloat($0) } ?? 0.0
                        let y = args["y"].flatMap { Double($0) }.map { CGFloat($0) } ?? 0.0
                        let distanceX = args["distanceX"].flatMap { Double($0) }.map { CGFloat($0) } ?? 0.0
                        let distanceY = args["distanceY"].flatMap { Double($0) }.map { CGFloat($0) } ?? 0.0
                        declaredFunctionCall = .scroll(x: x, y: y, distanceX: distanceX, distanceY: distanceY)
                    } else if functionNameString == GeminiFunctionName.swipe.rawValue {
                        let x = args["x"].flatMap { Double($0) }.map { CGFloat($0) } ?? 0.0
                        let y = args["y"].flatMap { Double($0) }.map { CGFloat($0) } ?? 0.0
                        let direction = args["direction"].flatMap { SwipeDirection(rawValue: $0) } ?? .down // Default if missing/invalid
                        declaredFunctionCall = .swipe(x: x, y: y, direction: direction)
                    } else {
                        throw Error.invalidTool(name: functionNameString, message: "Unknown function name.")
                    }

                    guard let validFunctionCall = declaredFunctionCall else {
                        throw Error.invalidTool(name: functionNameString, message: "Could not reconstruct declared function call.")
                    }

                    // Execute the function call using the existing logic but with GeminiDeclaredFunctionCall
                    switch validFunctionCall {
                    case let .tapElement(coordinate, count, longPress):
                        try tapElement(rect: coordinate, count: count, longPress: longPress)
                    case .fetchAccessibilityTree:
                        print("Getting current accessibility tree")
                    case let .enterText(coordinate, text):
                        try await enterText(rect: coordinate, text: text)
                    case .openApp(let bundleIdentifier):
                        let appToOpen = XCUIApplication(bundleIdentifier: bundleIdentifier)
                        if bundleIdentifier == "com.apple.springboard" {
                            appToOpen.activate()
                        } else {
                            appToOpen.launch()
                        }
                        self.app = appToOpen // Update the reference to the current app
                    case let .scroll(x, y, distanceX, distanceY):
                        try scroll(x: x, y: y, distanceX: distanceX, distanceY: distanceY)
                    case let .swipe(x, y, direction):
                        try swipe(x: x, y: y, direction: direction)
                    }
                    guard let app = self.app else { // Ensure self.app is used
                        throw Error.noAppFound
                    }
                    output = app.accessibilityTree()
                } catch {
                    output = "Error executing function call: \(error.localizedDescription)"
                }

                // Prepare for the next recurse call by sending the function response
                let funcResponseData = GeminiFunctionResponseData(output: ["result": output]) // name is part of GeminiFunctionResponsePart
                let partResponse = GeminiPart(functionResponse: GeminiFunctionResponsePart(name: functionNameString, response: funcResponseData))
                let toolResponseContent = GeminiContent(role: "tool", parts: [partResponse])

                var nextRequest = currentRequest // Start with the current request to preserve history
                nextRequest.contents.append(toolResponseContent) // Add the tool's response

                // lastRequest should reflect the state *before* this tool response is added,
                // so handleQuickReply can correctly append a user message to that state.
                // However, the recursive call *needs* the tool response.
                // This means handleQuickReply should probably use the 'request' passed to recurse,
                // before it's augmented with the tool response.
                // For now, lastRequest was set before this loop.

                try await recurse(with: nextRequest)

            } else if let _ = part.functionResponse {
                // This case handles when Gemini sends back a functionResponse.
                // Generally, the model would follow up with text or another function call.
                // If this part is hit, it means the model just confirmed our function execution result.
                // We might not need to do anything specific here unless the next part (or next candidate) has further instructions.
                print("Received function response confirmation from model (should not happen based on current flow): \(part.functionResponse!)")
            }
        }
    }
}

// Tools
extension PhoneAgent {

    @MainActor
    func tapElement(rect coordinateString: String, count: Int?, longPress: Bool?) throws {
        guard let app else {
            throw Error.noAppFound
        }
        let coordinate = NSCoder.cgRect(for: coordinateString)
        let midPoint = CGPoint(x: coordinate.midX, y: coordinate.midY)
        let startCoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let targetCoordinate = startCoordinate.withOffset(CGVector(dx: midPoint.x, dy: midPoint.y))
        if longPress == true {
            targetCoordinate.press(forDuration: 0.5)
        } else {
            if count == 2 {
                targetCoordinate.doubleTap()
            } else {
                targetCoordinate.tap()
            }
        }
    }

    @MainActor
    func scroll(x: CGFloat, y: CGFloat, distanceX: CGFloat, distanceY: CGFloat) throws {
        guard let app else {
            throw Error.noAppFound
        }
        let mid  = CGPoint(x: x, y: y)

        let root = app.coordinate(withNormalizedOffset: .zero)

        let start = root.withOffset(CGVector(dx: mid.x, dy: mid.y))

        let end = root.withOffset(CGVector(dx: mid.x + distanceX, dy: mid.y + distanceY))

        start.press(forDuration: 0, thenDragTo: end)
    }

    @MainActor
    func swipe(x: CGFloat, y: CGFloat, direction: SwipeDirection) throws {
        guard let app else {
            throw Error.noAppFound
        }
        let mid = CGPoint(x: x, y: y)

        // Root (0,0) of the screen
        let root = app.coordinate(withNormalizedOffset: .zero)

        let start = root.withOffset(CGVector(dx: mid.x, dy: mid.y))

        let end: XCUICoordinate
        switch direction {
        case .up:
            end = root.withOffset(CGVector(dx: mid.x, dy: mid.y - 100))
        case .down:
            end = root.withOffset(CGVector(dx: mid.x, dy: mid.y + 100))
        case .left:
            end = root.withOffset(CGVector(dx: mid.x - 100, dy: mid.y))
        case .right:
            end = root.withOffset(CGVector(dx: mid.x + 100, dy: mid.y))
        }

        start.press(forDuration: 0.1, thenDragTo: end)
    }

    @MainActor
    func enterText(rect: String, text: String) async throws {
        guard let app else {
            throw Error.noAppFound
        }
        try tapElement(rect: rect, count: 1, longPress: false)
        let keyboard = app.keyboards.element
        let existsPredicate = NSPredicate(format: "exists == true")

        let exp = expectation(for: existsPredicate, evaluatedWith: keyboard, handler: nil)
        await fulfillment(of: [exp], timeout: 2, enforceOrder: false)

        app.typeText(text + "\n")
    }
}

extension PhoneAgent: UNUserNotificationCenterDelegate {

    private enum NotificationConstants {
        static let categoryIdentifier = "PUA_CATEGORY"
        static let replyActionIdentifier = "REPLY_ACTION"
    }

    func sendNotification(message: String) async throws {

        let replyAction = UNTextInputNotificationAction(
            identifier: NotificationConstants.replyActionIdentifier,
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type your reply..."
        )

        let category = UNNotificationCategory(
            identifier: NotificationConstants.categoryIdentifier,
            actions: [replyAction],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([category])

        let content = UNMutableNotificationContent()
        content.title = "Phone Agent"
        content.body = message
        content.sound = .default
        content.categoryIdentifier = NotificationConstants.categoryIdentifier

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        try await notificationCenter.add(request)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard response.actionIdentifier == NotificationConstants.replyActionIdentifier else {
            print("Received unexpected notification response with action: \(response.actionIdentifier)")
            return
        }
        guard let textResponse = response as? UNTextInputNotificationResponse else { return }
        let userText = textResponse.userText
        handleQuickReply(text: userText)
    }

    func handleQuickReply(text: String) {
        guard var requestForReply = lastRequest else { // Use lastRequest which reflects the state before the previous model response processing.
            print("No lastRequest found to handle quick reply.")
            return
        }

        // Append the user's new text as a new user content part.
        let userReplyContent = GeminiContent(role: "user", parts: [GeminiPart(text: text)])
        requestForReply.contents.append(userReplyContent)

        // The `lastRequest` should now be this new state before calling recurse again.
        lastRequest = requestForReply

        Task {
            do {
                try await recurse(with: requestForReply)
            } catch {
                print("Error handling quick reply: \(error)")
            }
        }
    }
}

struct AccessibilityTreeCompressor {
    let memoryAddressRegex = try! NSRegularExpression(pattern: #"0x[0-9a-fA-F]+"#)
    func callAsFunction(_ tree: String) -> String {
        let cleaned = memoryAddressRegex.stringByReplacingMatches(
            in: tree,
            range: NSRange(tree.startIndex..., in: tree),
            withTemplate: ""
        ).replacingOccurrences(of: ", ,", with: ",")

        // Remove low-information “Other” lines
        let keptLines = cleaned
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Only look at nodes that start with “Other,”
                guard trimmed.hasPrefix("Other,") else { return true }

                // Keep if it still shows anything useful
                return trimmed.contains("identifier:")
                    || trimmed.contains("label:")
                    || trimmed.contains("placeholderValue:")
            }

        return keptLines.joined(separator: "\n")
    }
}

extension XCUIApplication {
    static let treeCompressor = AccessibilityTreeCompressor()
    func accessibilityTree() -> String {
        Self.treeCompressor(debugDescription)
    }
}
