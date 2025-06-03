import Foundation

// MARK: - Gemini Tool and Function Calling Structures

// Represents the arguments for a function call as understood by the model/API.
// This enum defines the *specific arguments* for each known function.
// It's used after parsing the model's function call request.
enum GeminiDeclaredFunctionCall: Codable, Equatable {
    case enterText(coordinate: String, text: String)
    case fetchAccessibilityTree
    case openApp(bundleIdentifier: String)
    case tapElement(coordinate: String, count: Int?, longPress: Bool?)
    case scroll(x: CGFloat, y: CGFloat, distanceX: CGFloat, distanceY: CGFloat)
    case swipe(x: CGFloat, y: CGFloat, direction: SwipeDirection)

    // Custom coding logic might be needed if Gemini's args format for specific functions
    // doesn't directly map to these cases. For now, relying on default Codable synthesis
    // or specific decoding in the part that handles `GeminiFunctionCallPart`.
}

// Renamed from Tool.Name, represents the names of functions the model can call.
enum GeminiFunctionName: String, Codable {
    case enterText
    case fetchAccessibilityTree
    case openApp
    case tapElement
    case scroll
    case swipe
}

// Renamed from Property, describes a single parameter in a function's definition.
struct GeminiParameterProperty: Codable, Equatable {
    let type: String // e.g., "string", "integer", "number", "boolean", "object", "array"
    let description: String
    // Add other fields like `enum` (for allowed string values), `items` (for array type),
    // `properties` (for object type) if needed by the Gemini API for richer parameter definitions.
}

// Renamed from Parameters, describes the overall parameters for a function.
struct GeminiFunctionParameters: Codable, Equatable {
    let type: String // Typically "object" for functions with multiple parameters.
    let properties: [String: GeminiParameterProperty]
    let required: [String]? // List of required parameter names.
}

// Describes a single function that the model can declare its intent to call.
struct GeminiFunctionDeclaration: Codable, Equatable {
    let name: String // The name of the function, matching one of GeminiFunctionName rawValues.
    let description: String // Description of what the function does.
    let parameters: GeminiFunctionParameters? // Parameters the function accepts.
}

// Replaces the old Tool struct. This is what's included in the GeminiRequest.
struct GeminiTool: Codable, Equatable { // Replaces placeholder
    let functionDeclarations: [GeminiFunctionDeclaration]?
}

// Configuration for how the model should use tools (functions).
struct GeminiFunctionCallingConfig: Codable, Equatable {
    enum Mode: String, Codable {
        case AUTO // Model decides whether to call functions.
        case ANY  // Model must call one of the provided functions.
        case NONE // Model will not call any functions.
    }
    let mode: Mode?
    let allowedFunctionNames: [String]? // If mode is ANY, specifies which functions are allowed.
}

struct ToolConfig: Codable, Equatable { // Replaces placeholder
    let functionCallingConfig: GeminiFunctionCallingConfig?
    // Potentially other tool-related configs could go here in the future.
}


// MARK: - Gemini Request/Response Content Parts

// Part of `GeminiContent`, representing a function call *requested by the model*.
struct GeminiFunctionCallPart: Codable, Equatable { // Replaces placeholder
    let name: String // Function name the model wants to call.
    // Gemini typically sends `args` as a JSON object.
    // Using `[String: AnyCodable]` would be robust, but requires an AnyCodable type.
    // For simplicity, if args are flat key-value pairs of strings, `[String: String]` can work.
    // If structure is more complex or types vary, `[String: Foundation.JSONValue]` or a custom solution is needed.
    // For now, let's assume it will be decoded into a suitable dictionary or specific struct later.
    // This example will use [String: String] and acknowledge it might need to be more complex.
    let args: [String: String]? // Simplified for now.
}

// Part of `GeminiContent`, representing the *result of a function call* (client to model).
struct GeminiFunctionResponseData: Codable, Equatable {
    // `name` here refers to the function whose result this is.
    // It's part of the `response` object within `GeminiFunctionResponsePart`.
    // The Gemini API expects something like: { "name": "function_name", "content": { ... actual output ... }}
    // So this struct represents the `content` part of that.
    // Let's simplify to a dictionary, but this would ideally be structured per function.
    let output: [String: String] // Simplified output.
                                 // Consider making this `[String: AnyCodable]` or specific types per function.
}

struct GeminiFunctionResponsePart: Codable, Equatable { // Replaces placeholder
    let name: String // The name of the function that was executed.
    let response: GeminiFunctionResponseData // The result of the function execution.
}

struct GeminiPart: Codable, Equatable {
    let text: String?
    let functionCall: GeminiFunctionCallPart? // Model requests a function call.
    let functionResponse: GeminiFunctionResponsePart? // Client provides function result.

    init(text: String? = nil, functionCall: GeminiFunctionCallPart? = nil, functionResponse: GeminiFunctionResponsePart? = nil) {
        self.text = text
        self.functionCall = functionCall
        self.functionResponse = functionResponse
    }
}

struct GeminiContent: Codable, Equatable {
    let role: String // "user" or "model"
    let parts: [GeminiPart]
}

// Structs for Gemini Response (already defined and should be compatible)
struct GeminiSafetyRating: Codable, Equatable {
    let category: String?
    let probability: String?
}

struct GeminiCitationSource: Codable, Equatable {
    let uri: String?
}

struct GeminiCitationMetadata: Codable, Equatable {
    let citationSources: [GeminiCitationSource]?
}

struct GeminiCandidate: Codable, Equatable {
    let content: GeminiContent?
    let finishReason: String?
    let citationMetadata: GeminiCitationMetadata?
    let safetyRatings: [GeminiSafetyRating]?
}

struct GeminiPromptFeedback: Codable, Equatable {
    let safetyRatings: [GeminiSafetyRating]?
}

struct GeminiResponse: Codable, Equatable {
    let candidates: [GeminiCandidate]?
    let promptFeedback: GeminiPromptFeedback?
}

// Keep SwipeDirection as it's used by GeminiDeclaredFunctionCall
enum SwipeDirection: String, Codable {
    case up, down, left, right
}

struct GeminiRequest: Encodable {
    let model: String
    var contents: [GeminiContent]
    let tools: [GeminiTool]? // This should now correctly use the new GeminiTool struct
    var previousResponseID: String? = nil // May not be used by Gemini's generateContent in the same way.
    let toolConfig: ToolConfig?
}

class GeminiService {
    private let apiKey: String

    init(with apiKey: String) {
        self.apiKey = apiKey
    }

    func send(_ payload: GeminiRequest) async throws -> GeminiResponse {
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key=\(apiKey)")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // Serialize the JSON payload
        let jsonData = try JSONEncoder.shared.encode(payload)
        request.httpBody = jsonData
        return try await URLSession.shared.fetch(for: request)
    }

}

extension GeminiRequest {
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
        // This initializer will be completely reworked later.
        // For now, creating a placeholder GeminiContent to satisfy the type change.
        let combinedPrompt = systemPrompt + "\n" + prompt
        let userContent = GeminiContent(role: "user", parts: [GeminiPart(text: combinedPrompt)])

        self = GeminiRequest(
            model: "gemini-1.5-flash-latest",
            contents: [userContent],
            tools: nil, // This will be updated later to be [GeminiTool]?
            toolConfig: nil // This will be updated later
            // previousResponseID is not set here
        )
    }
}

// The old `extension Tool` and `extension [Tool]` are now removed.
// New extensions for GeminiTool will be added in Step 8.

extension GeminiTool {
    static func enterTextDeclaration() -> GeminiFunctionDeclaration {
        GeminiFunctionDeclaration(
            name: GeminiFunctionName.enterText.rawValue,
            description: "Enter text into a text field. Responds with an updated accessibility tree of the current app.",
            parameters: GeminiFunctionParameters(
                type: "object",
                properties: [
                    "coordinate": GeminiParameterProperty(
                        type: "string",
                        description: "Pass back the coordinate from the tree that corresponds to the element to enter text into. It should look like: {{0.0, 56.3}, {402.0, 44.0}}"
                    ),
                    "text": GeminiParameterProperty(
                        type: "string",
                        description: "The text to enter into the text field."
                    )
                ],
                required: ["coordinate", "text"]
            )
        )
    }

    static func fetchAccessibilityTreeDeclaration() -> GeminiFunctionDeclaration {
        GeminiFunctionDeclaration(
            name: GeminiFunctionName.fetchAccessibilityTree.rawValue,
            description: "Get a refreshed accessibility tree of the current app. Useful when a tap will update the app UI",
            parameters: nil // No parameters for this function
        )
    }

    static func openAppDeclaration() -> GeminiFunctionDeclaration {
        GeminiFunctionDeclaration(
            name: GeminiFunctionName.openApp.rawValue,
            description: "Opens a different app on the iPhone. Responds with an accessibility tree of the new app.",
            parameters: GeminiFunctionParameters(
                type: "object",
                properties: [
                    "bundle_identifier": GeminiParameterProperty( // Assuming snake_case for parameter names if that's what the functions expect
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

    static func tapElementDeclaration() -> GeminiFunctionDeclaration {
        GeminiFunctionDeclaration(
            name: GeminiFunctionName.tapElement.rawValue,
            description: "Tap the element with the specified coordinate. Responds with an updated accessibility tree of the current app.",
            parameters: GeminiFunctionParameters(
                type: "object",
                properties: [
                    "coordinate": GeminiParameterProperty(
                        type: "string",
                        description: "Pass back the coordinate from the tree that corresponds to the element to tap. It should look like: {{0.0, 56.3}, {402.0, 44.0}}"
                    ),
                    "count": GeminiParameterProperty(
                        type: "integer",
                        description: "The number of times to tap the element. 1 for a single tap, 2 for a double tap. Defaults to 1"
                    ),
                    "longPress": GeminiParameterProperty( // Changed from long_press to longPress to match typical Swift style
                        type: "boolean",
                        description: "Whether to long press the element. Defaults to false"
                    )
                ],
                required: ["coordinate"]
            )
        )
    }

    static func scrollDeclaration() -> GeminiFunctionDeclaration {
        GeminiFunctionDeclaration(
            name: GeminiFunctionName.scroll.rawValue,
            description: "Scroll the current app's content by a specified distance in horizontal and vertical directions. Responds with an updated accessibility tree of the current app.",
            parameters: GeminiFunctionParameters(
                type: "object",
                properties: [
                    "x": GeminiParameterProperty(type: "number", description: "The x coordinate of the element to scroll from, in absolute coordinates"),
                    "y": GeminiParameterProperty(type: "number", description: "The y coordinate of the element to scroll from, in absolute coordinates"),
                    "distanceX": GeminiParameterProperty(type: "number", description: "The distance to scroll in the x direction."),
                    "distanceY": GeminiParameterProperty(type: "number", description: "The distance to scroll in the y direction.")
                ],
                required: ["x", "y", "distanceX", "distanceY"]
            )
        )
    }

    static func swipeDeclaration() -> GeminiFunctionDeclaration {
        GeminiFunctionDeclaration(
            name: GeminiFunctionName.swipe.rawValue,
            description: "Swipe in a specified direction from a given coordinate. Responds with an updated accessibility tree of the current app.",
            parameters: GeminiFunctionParameters(
                type: "object",
                properties: [
                    "x": GeminiParameterProperty(type: "number", description: "The x coordinate of the element to swipe from, in absolute coordinates"),
                    "y": GeminiParameterProperty(type: "number", description: "The y coordinate of the element to swipe from, in absolute coordinates"),
                    "direction": GeminiParameterProperty(
                        type: "string",
                        description: "The direction to swipe in. Valid values are 'up', 'down', 'left', 'right'." // Potentially add enum here if supported
                    )
                ],
                required: ["x", "y", "direction"]
            )
        )
    }

    static func allDeclarations() -> [GeminiFunctionDeclaration] {
        return [
            enterTextDeclaration(),
            fetchAccessibilityTreeDeclaration(),
            openAppDeclaration(),
            tapElementDeclaration(),
            scrollDeclaration(),
            swipeDeclaration()
        ]
    }
}

extension GeminiRequest {
    init(with prompt: String, accessibilityTree: String? = nil) {
        var fullPrompt = ""
        // Gemini doesn't have a dedicated system role in the same way as OpenAI.
        // System instructions are typically prepended to the first user message.
        var systemInstructions = """
                              You are an iPhone using assistant that helps the user accomplish their tasks.
                              You can multiple tools available, and it might take multiple steps to complete a task.
                              Never ask the user what they want to do, just perform the action.
                              """
        fullPrompt += systemInstructions

        if let accessibilityTree {
            fullPrompt += """
                          \nHere is the accessibility tree of the currently open app: \(accessibilityTree)
                          Depending on the user's request, you can perform actions in the current app, or open a different app
                          """
        }

        fullPrompt += "\n\nUser prompt: \(prompt)"

        let userContent = GeminiContent(role: "user", parts: [GeminiPart(text: fullPrompt)])

        let declarations = GeminiTool.allDeclarations()
        let currentTools: [GeminiTool]? = declarations.isEmpty ? nil : [GeminiTool(functionDeclarations: declarations)]
        let currentToolConfig: ToolConfig? = declarations.isEmpty ? nil : ToolConfig(functionCallingConfig: GeminiFunctionCallingConfig(mode: .AUTO, allowedFunctionNames: nil))

        self = GeminiRequest(
            model: "gemini-1.5-flash-latest",
            contents: [userContent],
            tools: currentTools,
            toolConfig: currentToolConfig
        )
    }
}

extension URLSession {
    func fetch<T: Decodable>(for request: URLRequest) async throws -> T {
        let (data, response) = try await data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // Improved error handling for Gemini (Step 10) will go here or be called from here
            let responseString = String(data: data, encoding: .utf8) ?? "No response data"
            print("Invalid response received. Status: \(httpResponse.statusCode). Response: \(responseString)")
            // Attempt to decode GeminiError
            if let geminiError = try? JSONDecoder.shared.decode(GeminiErrorResponse.self, from: data) {
                throw geminiError
            }
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder.shared.decode(T.self, from: data)
    }
}

// Define GeminiErrorResponse and related structs for Step 10
struct GeminiError: Codable {
    let code: Int?
    let message: String?
    let status: String?
}

struct GeminiErrorResponse: Codable, Error {
    let error: GeminiError
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
        // Using default strategy (camelCase from Swift properties) for requests to Gemini,
        // as Gemini API examples often show camelCase for request fields like 'functionDeclarations'.
        encoder.keyEncodingStrategy = .useDefaultKeys
        return encoder
    }()
}
