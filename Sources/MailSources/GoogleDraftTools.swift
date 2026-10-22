import Foundation

/// Gmail and Drive lookups for Claude while it drafts. Read-only.
public struct GoogleDraftTools: DraftTools {
    private let gmail: GmailSource
    private let drive: DriveClient

    public init(gmail: GmailSource, drive: DriveClient) {
        self.gmail = gmail
        self.drive = drive
    }

    public var definitions: [ClaudeTool] {
        [
            tool("search_gmail", "Search this mailbox with Gmail search syntax, e.g. `from:sam invoice newer_than:30d` "
                 + "or `subject:\"term sheet\"`. Returns up to 8 messages, newest first, with id, sender, date, subject and a snippet.",
                 field: "query", about: "Gmail search query"),
            tool("read_email", "Read one email from this mailbox in full, by the id from search_gmail.",
                 field: "id", about: "Message id"),
            tool("search_drive", "Full-text search in Google Drive (file names and contents, including shared drives). "
                 + "Returns up to 8 files with id, name, type, modified date and link.",
                 field: "query", about: "Words to search for"),
            tool("read_drive_file", "Read a Google Doc, Sheet (as CSV), Slides deck or text file by the id from search_drive. Long files are cut.",
                 field: "id", about: "File id"),
        ]
    }

    public func run(_ call: ClaudeToolUse) async -> DraftToolResult {
        guard let value = call.input["query"]?.stringValue ?? call.input["id"]?.stringValue else {
            return DraftToolResult(text: "Missing input", isError: true)
        }
        do {
            switch call.name {
            case "search_gmail": return DraftToolResult(text: try await gmail.search(value))
            case "read_email": return DraftToolResult(text: try await gmail.readMessage(value))
            case "search_drive": return DraftToolResult(text: try await drive.search(value))
            case "read_drive_file": return DraftToolResult(text: try await drive.read(value))
            default: return DraftToolResult(text: "Unknown tool \(call.name)", isError: true)
            }
        } catch MailSourceError.http(status: 403, let message) where call.name.contains("drive") && Self.isMissingAccess(message) {
            return DraftToolResult(text: "Drive access isn't granted yet. Continue without Drive.", isError: true)
        } catch {
            return DraftToolResult(text: "Failed: \(error.localizedDescription)", isError: true)
        }
    }

    public func describe(_ call: ClaudeToolUse) -> String {
        let value = call.input["query"]?.stringValue.map { ": \($0.prefix(40))" } ?? ""
        switch call.name {
        case "search_gmail": return "Searching Gmail\(value)"
        case "read_email": return "Reading an email"
        case "search_drive": return "Searching Drive\(value)"
        case "read_drive_file": return "Reading a Drive file"
        default: return "Looking something up"
        }
    }

    /// Scope not granted or API off, as opposed to rate limits or one file being off-limits.
    static func isMissingAccess(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return ["insufficient", "scope", "has not been used", "is disabled"].contains { lowered.contains($0) }
    }

    private func tool(_ name: String, _ description: String, field: String, about: String) -> ClaudeTool {
        ClaudeTool(name: name, description: description, inputSchema: .object([
            "type": .string("object"),
            "properties": .object([field: .object(["type": .string("string"), "description": .string(about)])]),
            "required": .array([.string(field)]),
            "additionalProperties": .bool(false),
        ]))
    }
}
