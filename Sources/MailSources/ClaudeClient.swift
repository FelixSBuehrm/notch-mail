import Foundation

/// The Anthropic API key, plus the workspace ID when the key isn't tied to one.
public struct ClaudeCredentials: Sendable {
    public let apiKey: String
    public let workspaceID: String?

    public init(apiKey: String, workspaceID: String?) {
        self.apiKey = apiKey
        self.workspaceID = workspaceID
    }
}

/// A tool Claude may call. The schema is strict: inputs always match it.
public struct ClaudeTool: Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    var json: JSONValue {
        .object(["name": .string(name), "description": .string(description), "input_schema": inputSchema, "strict": .bool(true)])
    }
}

public struct ClaudeToolUse: Equatable, Sendable {
    public let id: String
    public let name: String
    public let input: JSONValue
}

/// One answer from Claude. `content` is kept exactly as received.
public struct ClaudeResponse: Sendable {
    public let content: [JSONValue]
    public let stopReason: String?

    public var text: String {
        content.filter { $0["type"]?.stringValue == "text" }.compactMap { $0["text"]?.stringValue }.joined()
    }

    public var toolUses: [ClaudeToolUse] {
        content.compactMap { block in
            guard block["type"]?.stringValue == "tool_use",
                  let id = block["id"]?.stringValue, let name = block["name"]?.stringValue else { return nil }
            return ClaudeToolUse(id: id, name: name, input: block["input"] ?? .object([:]))
        }
    }
}

public enum ClaudeError: Error, Equatable, LocalizedError {
    case missingKey
    case rejectedKey
    case busy
    case http(status: Int, message: String)
    case refused
    case truncated
    case tooManySteps
    case emptyDraft
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .missingKey: "No Anthropic API key in the Keychain (notchmail.anthropic)"
        case .rejectedKey: "Anthropic rejected the API key"
        case .busy: "Claude is busy right now, try again in a moment"
        case .http(let status, let message): "Claude error \(status): \(message)"
        case .refused: "Claude declined to write this reply"
        case .truncated: "The draft got too long; try a shorter instruction"
        case .tooManySteps: "Claude searched too long without finishing; try a more specific instruction"
        case .emptyDraft: "Claude returned an empty draft"
        case .invalidResponse: "Unexpected answer from Claude"
        }
    }
}

/// The Messages API over plain HTTPS (there is no official Swift SDK).
public struct ClaudeClient: Sendable {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    /// Writes the drafts. Sonnet: quick and good at short, natural text.
    public static let model = "claude-sonnet-5-5"
    static let maxTokens = 16_000
    static let timeout: TimeInterval = 120

    private let credentials: ClaudeCredentials
    private let transport: any HTTPTransport

    public init(credentials: ClaudeCredentials, transport: any HTTPTransport) {
        self.credentials = credentials
        self.transport = transport
    }

    public func send(system: String, messages: [JSONValue], tools: [ClaudeTool]) async throws -> ClaudeResponse {
        let (data, response) = try await transport.send(request(system: system, messages: messages, tools: tools))
        switch response.statusCode {
        case 200..<300:
            struct Body: Decodable {
                let content: [JSONValue]
                let stop_reason: String?
            }
            guard let body = try? JSONDecoder().decode(Body.self, from: data) else { throw ClaudeError.invalidResponse }
            return ClaudeResponse(content: body.content, stopReason: body.stop_reason)
        case 401, 403:
            throw ClaudeError.rejectedKey
        case 429, 529:
            throw ClaudeError.busy
        default:
            let message = (try? JSONDecoder().decode(JSONValue.self, from: data))?["error"]?["message"]?.stringValue
            throw ClaudeError.http(status: response.statusCode, message: message ?? "no details")
        }
    }

    func request(system: String, messages: [JSONValue], tools: [ClaudeTool]) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        // On a declined request the API retries it on a fallback model by itself.
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        if let workspace = credentials.workspaceID, !workspace.isEmpty {
            request.setValue(workspace, forHTTPHeaderField: "anthropic-workspace-id")
        }
        let body: JSONValue = .object([
            "model": .string(Self.model),
            "max_tokens": .number(Double(Self.maxTokens)),
            "system": .string(system),
            "messages": .array(messages),
            "tools": .array(tools.map(\.json)),
            "output_config": .object(["effort": .string("medium")]),
            // The system prompt and tools repeat on every step of the tool loop.
            "cache_control": .object(["type": .string("ephemeral")]),
            "fallbacks": .string("default"),
        ])
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}
