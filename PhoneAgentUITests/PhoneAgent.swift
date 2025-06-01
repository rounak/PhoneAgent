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
        try await recurse(with: OpenAIRequest(with: prompt, accessibilityTree: app.map { $0.accessibilityTree() }))
    }

    @MainActor
    private func recurse(with request: OpenAIRequest) async throws {
        guard let api else {
            throw Error.apiNotConfigured
        }
        var request = request
        let response = try await api.send(request)
        guard let last = response.output.last else { fatalError("No response received.") }
        print("Received message \(last)")
        request.input = []
        request.previousResponseID = response.id
        lastRequest = request
        let output: String
        switch last {
        case .functionCall(let id, let functionCall):
            do {
                switch functionCall {
                case let .tapElement(coordinate, count, longPress):
                    try tapElement(rect: coordinate, count: count, longPress: longPress)
                case .fetchAccessibilityTree:
                    print("Getting current accessibility tree")
                case let .enterText(coordinate, text):
                    try await enterText(rect: coordinate, text: text)
                case .openApp(let bundleIdentifier):
                    let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
                    app.activate()
                    self.app = app
                case let .scroll(x: x, y:y, distanceX: distanceX, distanceY: distanceY):
                    try scroll(x: x, y: y, distanceX: distanceX, distanceY: distanceY)
                case let .swipe(x: x, y: y, direction: direction):
                    try swipe(x: x, y: y, direction: direction)
                }
                guard let app else {
                    throw Error.noAppFound
                }
                output = app.accessibilityTree()
            } catch {
                output = "Error executing function call: \(error.localizedDescription)"
            }
            request.input.append(.functionCallOutput(id, output: output))
            try await recurse(with: request)
        case .message(let message):
            Task {
                do {
                    try await sendNotification(message: message.content.first { $0.type == .outputText }?.text ?? "Completed")
                } catch {
                    print(error)
                }
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
        guard var lastRequest else {
            print("No last request found.")
            return
        }
        lastRequest.input = [
            .user(text)
        ]
        Task {
            do {
                try await recurse(with: lastRequest)
            } catch {
                print(error)
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
