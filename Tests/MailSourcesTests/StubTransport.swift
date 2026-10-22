import Foundation
@testable import MailSources

/// Answers requests from a script and records what was sent.
actor StubTransport: HTTPTransport {
    struct Reply {
        let status: Int
        let body: Data
    }

    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let reply = replies.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
        return (reply.body, response)
    }
}

extension StubTransport.Reply {
    static func json(_ text: String, status: Int = 200) -> Self {
        Self(status: status, body: Data(text.utf8))
    }
}

func base64URL(_ text: String) -> String {
    Data(text.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func formFields(_ request: URLRequest) -> [String: String] {
    let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
    var fields: [String: String] = [:]
    for pair in body.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { continue }
        fields[parts[0]] = parts[1].removingPercentEncoding
    }
    return fields
}
