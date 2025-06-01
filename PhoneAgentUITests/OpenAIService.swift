import Foundation

struct Message: Encodable {
    enum Role: String, Encodable {
        case system
        case user
    }
    enum `Type`: String, Encodable {
        case functionCallOutput = "function_call_output"
    }
    private var role: Role? = nil
    private var content: String? = nil
    private var callID: String? = nil
    private var type: `Type`?
    private var output: String?

    static func system(_ content: String) -> Message {
        Message(role: .system, content: content)
    }
    static func user(_ content: String) -> Message {
        Message(role: .user, content: content)
    }
    static func functionCallOutput(_ callID: String, output: String) -> Message {
        Message(callID: callID, type: .functionCallOutput, output: output)
    }
}

struct Content: Decodable, Equatable {
    enum `Type`: String, Decodable, Equatable {
        case outputText = "output_text"
    }
    let type: `Type`
    let text: String
}

enum Output: Decodable, Equatable {
    enum `Type`: String, Codable, Equatable {
        case functionCall = "function_call"
        case message
    }
    struct Message: Decodable, Equatable {
        let content: [Content]
    }
    case message(Message)
    case functionCall(id: String, Tool.FunctionCall)

    enum CodingKeys: String, CodingKey, Equatable {
        case type
        case callId
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(`Type`.self, forKey: .type)

        switch type {
        case .message:
            self = .message(try Message(from: decoder))
        case .functionCall:
            self = .functionCall(id: try container.decode(String.self, forKey: .callId), try .init(from: decoder))
        }
    }
}


struct Response: Decodable, Equatable {
    let id: String
    let output: [Output]
}

struct Parameters: Encodable {
    let type: String
    let properties: [String: Property]
    let required: [String]

}
struct Property: Encodable {
    let type: String
    let description: String
}

struct Tool: Encodable {
    let type: String = "function"
    let name: Name
    let description: String
    let parameters: Parameters?
}

enum SwipeDirection: String, Codable {
    case up, down, left, right
}


extension Tool {
    enum Name: String, Codable {
        case enterText
        case fetchAccessibilityTree
        case openApp
        case tapElement
        case scroll
        case swipe
    }

    enum FunctionCall: Decodable, Equatable {
        case enterText(coordinate: String, text: String)
        case fetchAccessibilityTree
        case openApp(bundleIdentifier: String)
        case tapElement(coordinate: String, count: Int?, longPress: Bool?)
        case scroll(x: CGFloat, y: CGFloat, distanceX: CGFloat, distanceY: CGFloat)
        case swipe(x: CGFloat, y: CGFloat, direction: SwipeDirection)

        // MARK: - Coding

        private enum CodingKeys: String, CodingKey {
            case name
            case arguments
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let name = try container.decode(Tool.Name.self, forKey: .name)
            let argumentsData = try container.decodeIfPresent(String.self, forKey: .arguments).map { Data($0.utf8) }

            let jsonDecoder = JSONDecoder.shared

            switch name {
            case .enterText:
                guard let data = argumentsData else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .arguments,
                        in: container,
                        debugDescription: "`enterText` is missing its arguments payload"
                    )
                }
                struct Args: Decodable { let coordinate, text: String }
                let args = try jsonDecoder.decode(Args.self, from: data)
                self = .enterText(coordinate: args.coordinate, text: args.text)

            case .fetchAccessibilityTree:
                self = .fetchAccessibilityTree

            case .openApp:
                guard let data = argumentsData else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .arguments,
                        in: container,
                        debugDescription: "`openApp` is missing its arguments payload"
                    )
                }
                struct Args: Decodable { let bundleIdentifier: String }
                let args = try jsonDecoder.decode(Args.self, from: data)
                self = .openApp(bundleIdentifier: args.bundleIdentifier)

            case .tapElement:
                guard let data = argumentsData else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .arguments,
                        in: container,
                        debugDescription: "`tapElement` is missing its arguments payload"
                    )
                }
                struct Args: Decodable { let coordinate: String; let count: Int?; let longPress: Bool? }
                let args = try jsonDecoder.decode(Args.self, from: data)
                self = .tapElement(coordinate: args.coordinate, count: args.count, longPress: args.longPress)
            case .scroll:
                guard let data = argumentsData else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .arguments,
                        in: container,
                        debugDescription: "`scroll` is missing its arguments payload"
                    )
                }
                struct Args: Decodable {
                    let x, y, distanceX, distanceY: CGFloat
                }
                let args = try jsonDecoder.decode(Args.self, from: data)
                self = .scroll(x: args.x, y: args.y, distanceX: args.distanceX, distanceY: args.distanceY)
            case .swipe:
                guard let data = argumentsData else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .arguments,
                        in: container,
                        debugDescription: "`scroll` is missing its arguments payload"
                    )
                }
                struct Args: Decodable {
                    let x, y: CGFloat; let direction: SwipeDirection
                }
                let args = try jsonDecoder.decode(Args.self, from: data)
                self = .swipe(x: args.x, y: args.y, direction: args.direction)
            }
        }
    }
}


struct OpenAIRequest: Encodable {
    let model: String
    var input: [Message]
    let tools: [Tool]
    let toolChoice: String
    var previousResponseID: String? = nil
    let parallelToolCalls: Bool
}

class OpenAIService {
    private let apiKey: String

    init(with apiKey: String) {
        self.apiKey = apiKey
    }

    func send(_ payload: OpenAIRequest) async throws -> Response {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // Serialize the JSON payload
        let jsonData = try JSONEncoder.shared.encode(payload)
        request.httpBody = jsonData
        return try await URLSession.shared.fetch(for: request)
    }

}

extension OpenAIRequest {
    init(with prompt: String, accessibilityTree: String? = nil) {
        var systemPrompt = """
                              You are an iPhone using assistant that helps the user accomplish their tasks.
                              You can multiple tools available, and it might take multiple steps to complete a task.
                              Never ask the user what they want to do, just perform the action.
                              """

        if let accessibilityTree {
          systemPrompt += """
                          \nHere is the accessibility tree of the currently open app: \(accessibilityTree)
                          Depending on the user's request, you can perform actions in the current app, or open a different app
                          """
        }
        let messages: [Message] = [
            .system(systemPrompt),
            .user(prompt)
        ]
        self = OpenAIRequest(
            model: "gpt-4.1",
            input: messages,
            tools: .all,
            toolChoice: "auto",
            parallelToolCalls: false
        )
    }
}

extension Tool {


    static func enterText() -> Tool {
        Tool(
            name: .enterText,
            description: "Enter text into a text field. Responds with an updated accessibility tree of the current app.",
            parameters: Parameters(
                type: "object",
                properties: [
                    "coordinate": Property(
                        type: "string",
                        description: "Pass back the coordinate from the tree that corresponds to the element to enter text into. It should look like: {{0.0, 56.3}, {402.0, 44.0}}"
                    ),
                    "text": Property(
                        type: "string",
                        description: "The text to enter into the text field."
                    )
                ],
                required: ["coordinate", "text"]
            )
        )
    }

    static func fetchAccessibilityTree() -> Tool {
        Tool(
            name: .fetchAccessibilityTree,
            description: "Get a refreshed accessibility tree of the current app. Useful when a tap will update the app UI",
            parameters: nil
        )
    }

    static func openApp() -> Tool {
        Tool(
            name: .openApp,
            description: "Opens a different app on the iPhone. Responds with an accessibility tree of the new app.",
            parameters: Parameters(
                type: "object",
                properties: [
                    "bundle_identifier": Property(
                        type: "string",
                        description:
                              """
                              The bundle identifier of the iOS app to open. Some common iOS apps: 
                              System Settings = com.apple.Preferences
                              Camera = com.apple.camera
                              Photos = com.apple.mobileslideshow
                              Messages = com.apple.MobileSMS
                              Home Screen = com.apple.springboard
                              Home screen will allow you to open system level features like Control Center (swipe from top right), Notification Center (swipe from top center), Spotlight (swipe down from the middle) etc.
                              """
                    )
                ],
                required: ["bundle_identifier"]
            )
        )
    }

    static func tapElement() -> Tool {
        Tool(
            name: .tapElement,
            description: "Tap the element with the specified coordinate. Responds with an updated accessibility tree of the current app.",
            parameters: Parameters(
                type: "object",
                properties: [
                    "coordinate": Property(
                        type: "string",
                        description: "Pass back the coordinate from the tree that corresponds to the element to tap. It should look like: {{0.0, 56.3}, {402.0, 44.0}}"
                    ),
                    "count": Property(
                        type: "integer",
                        description: "The number of times to tap the element. 1 for a single tap, 2 for a double tap. Defaults to 1"
                    ),
                    "longPress": Property(
                        type: "boolean",
                        description: "Whether to long press the element. Defaults to false"
                    )
                ],
                required: ["coordinate"]
            )
        )
    }

    static func scroll() -> Tool {
        Tool(
            name: .scroll,
            description: "Scroll the current app's content by a specified distance in horizontal and vertical directions. Responds with an updated accessibility tree of the current app.",
            parameters: Parameters(
                type: "object",
                properties: [
                    "x": Property(
                        type: "number",
                        description: "The x coordinate of the element to scroll from, in absolute coordinates"
                    ),
                    "y": Property(
                        type: "number",
                        description: "The y coordinate of the element to scroll from, in absolute coordinates"
                    ),
                    "distanceX": Property(
                        type: "number",
                        description: "The distance to scroll in the x direction."
                    ),
                    "distanceY": Property(
                        type: "number",
                        description: "The distance to scroll in the y direction."
                    )
                ],
                required: ["x", "y", "distanceX", "distanceY"]
            )
        )
    }

    static func swipe() -> Tool {
        Tool(
            name: .swipe,
            description: "Swipe in a specified direction from a given coordinate. Responds with an updated accessibility tree of the current app.",
            parameters: Parameters(
                type: "object",
                properties: [
                    "x": Property(
                        type: "number",
                        description: "The x coordinate of the element to swipe from, in absolute coordinates"
                    ),
                    "y": Property(
                        type: "number",
                        description: "The y coordinate of the element to swipe from, in absolute coordinates"
                    ),
                    "direction": Property(
                        type: "string",
                        description: "The direction to swipe in. Valid values are 'up', 'down', 'left', 'right'."
                    )
                ],
                required: ["x", "y", "direction"]
            )
        )
    }

}

extension [Tool] {
    static let all: [Tool] = [.enterText(),
                              .fetchAccessibilityTree(),
                              .openApp(),
                              .tapElement(),
                              .scroll(),
                              .swipe()]
}

extension URLSession {
    func fetch<T: Decodable>(for request: URLRequest) async throws -> T {
        let (data, response) = try await data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let responseString = String(data: data, encoding: .utf8) ?? "No response data"
            print("Invalid response received. Response: \(responseString)")
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder.shared.decode(T.self, from: data)
    }
}

extension JSONDecoder {
    static let shared: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

extension JSONEncoder {
    static let shared: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
}
