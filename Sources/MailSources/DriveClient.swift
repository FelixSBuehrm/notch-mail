import Foundation

/// Read-only Google Drive: full-text search and reading a file as text.
public struct DriveClient: Sendable {
    static let base = URL(string: "https://www.googleapis.com/drive/v3/files")!
    static let searchLimit = 8
    static let readLimit = 15_000

    private let google: APIRequester

    public init(tokens: GoogleTokenProvider, transport: any HTTPTransport) {
        google = APIRequester(tokens: tokens, transport: transport)
    }

    /// Words to look for in file names and contents.
    public func search(_ words: String) async throws -> String {
        let escaped = words.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        var components = URLComponents(url: Self.base, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "fullText contains '\(escaped)' and trashed = false"),
            URLQueryItem(name: "pageSize", value: String(Self.searchLimit)),
            URLQueryItem(name: "fields", value: "files(id,name,mimeType,modifiedTime,webViewLink)"),
            URLQueryItem(name: "corpora", value: "allDrives"),
            URLQueryItem(name: "includeItemsFromAllDrives", value: "true"),
            URLQueryItem(name: "supportsAllDrives", value: "true"),
        ]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        struct List: Decodable {
            struct File: Decodable {
                let id: String
                let name: String?
                let mimeType: String?
                let modifiedTime: String?
                let webViewLink: String?
            }
            let files: [File]?
        }
        let list: List = try await google.get(components.url!, what: "Drive search")
        let files = (list.files ?? []).filter { Self.isSafeID($0.id) }
        guard !files.isEmpty else { return "No files found." }
        return files.map { file in
            "id: \(file.id) | name: \(file.name ?? "?") | type: \(Self.kind(file.mimeType)) | modified: \(file.modifiedTime ?? "?") | link: \(file.webViewLink ?? "")"
        }.joined(separator: "\n")
    }

    /// Docs and Slides as text, Sheets as CSV, plain text files as they are.
    public func read(_ id: String) async throws -> String {
        guard Self.isSafeID(id) else { throw MailSourceError.invalidResponse("Unexpected file ID") }
        var meta = URLComponents(url: Self.base.appending(path: id), resolvingAgainstBaseURL: false)!
        meta.queryItems = [URLQueryItem(name: "fields", value: "id,name,mimeType"), URLQueryItem(name: "supportsAllDrives", value: "true")]
        struct Meta: Decodable {
            let name: String?
            let mimeType: String?
        }
        let file: Meta = try await google.get(meta.url!, what: "Drive file")
        let mime = file.mimeType ?? ""

        var content = URLComponents(url: Self.base.appending(path: id), resolvingAgainstBaseURL: false)!
        switch mime {
        case "application/vnd.google-apps.document", "application/vnd.google-apps.presentation":
            content = URLComponents(url: Self.base.appending(path: "\(id)/export"), resolvingAgainstBaseURL: false)!
            content.queryItems = [URLQueryItem(name: "mimeType", value: "text/plain")]
        case "application/vnd.google-apps.spreadsheet":
            content = URLComponents(url: Self.base.appending(path: "\(id)/export"), resolvingAgainstBaseURL: false)!
            content.queryItems = [URLQueryItem(name: "mimeType", value: "text/csv")]
        case _ where mime.hasPrefix("text/") || mime == "application/json":
            content.queryItems = [URLQueryItem(name: "alt", value: "media"), URLQueryItem(name: "supportsAllDrives", value: "true")]
        default:
            return "\(file.name ?? "This file") is a \(Self.kind(mime)); only Docs, Sheets, Slides and text files can be read."
        }
        let data = try await google.send(URLRequest(url: content.url!))
        let text = HTMLText.cleanDisplayText(String(decoding: data.prefix(Self.readLimit * 4), as: UTF8.self))
        let capped = text.count > Self.readLimit ? String(text.prefix(Self.readLimit)) + "\n[cut]" : text
        return "File: \(file.name ?? id)\n\n\(capped)"
    }

    static func isSafeID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 200 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    static func kind(_ mime: String?) -> String {
        switch mime {
        case "application/vnd.google-apps.document": "Google Doc"
        case "application/vnd.google-apps.spreadsheet": "Google Sheet"
        case "application/vnd.google-apps.presentation": "Google Slides"
        case "application/vnd.google-apps.folder": "folder"
        case "application/pdf": "PDF"
        case let other?: other
        case nil: "file"
        }
    }
}
