import Foundation
import Network

/// A one-shot web server on 127.0.0.1 that catches Google's redirect after
/// sign-in in the browser (the standard flow for desktop apps).
public final class LoopbackReceiver: @unchecked Sendable {
    // @unchecked: all mutable state is touched only on `queue`.
    private let queue = DispatchQueue(label: "notchmail.loopback")
    private let listener: NWListener
    private var continuation: CheckedContinuation<[String: String], Error>?
    /// A redirect that arrived before anyone was waiting for it.
    private var pending: [String: String]?
    private var readyContinuation: CheckedContinuation<URL, Error>?
    /// Only a redirect carrying this exact `state` is accepted, so another
    /// program on the Mac can't end the sign-in by guessing the port.
    private let expectedState: String
    static let connectionTimeout: TimeInterval = 5

    public init(expectedState: String) throws {
        self.expectedState = expectedState
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    /// Starts listening and returns the redirect URI to give Google.
    public func start() async throws -> URL {
        try await withCheckedThrowingContinuation { (ready: CheckedContinuation<URL, Error>) in
            queue.async { [self] in
                readyContinuation = ready
                listener.stateUpdateHandler = { [weak self] state in self?.listenerChanged(state) }
                listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
                listener.start(queue: queue)
            }
        }
    }

    /// Runs on `queue`.
    private func listenerChanged(_ state: NWListener.State) {
        guard let ready = readyContinuation else { return }
        switch state {
        case .ready:
            readyContinuation = nil
            ready.resume(returning: URL(string: "http://127.0.0.1:\(listener.port?.rawValue ?? 0)")!)
        case .failed(let error):
            readyContinuation = nil
            ready.resume(throwing: MailSourceError.signInFailed("Local listener: \(error)"))
        default:
            break
        }
    }

    /// Waits for the browser to come back with the query parameters (`code`, `state`).
    public func waitForRedirect(timeout: Duration = .seconds(300)) async throws -> [String: String] {
        try await withThrowingTaskGroup(of: [String: String].self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    self.queue.async {
                        if let pending = self.pending {
                            self.pending = nil
                            continuation.resume(returning: pending)
                        } else {
                            self.continuation = continuation
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw MailSourceError.signInFailed("No answer from the browser within 5 minutes")
            }
            defer { group.cancelAll(); stop() }
            guard let result = try await group.next() else {
                throw MailSourceError.signInFailed("Sign-in was cancelled")
            }
            return result
        }
    }

    public func stop() {
        queue.async { [self] in
            listener.cancel()
            continuation?.resume(throwing: MailSourceError.signInFailed("Sign-in was cancelled"))
            continuation = nil
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        // A connection that never sends anything shouldn't linger.
        queue.asyncAfter(deadline: .now() + Self.connectionTimeout) { connection.cancel() }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = String(decoding: data ?? Data(), as: UTF8.self)
            let query = Self.queryItems(fromRequest: request)
            // Browsers also ask for /favicon.ico; only "/" with our state counts.
            let isRedirect = query?["state"] == self.expectedState
                && (query?["code"] != nil || query?["error"] != nil)
            Self.respond(on: connection, success: query?["code"] != nil, isRedirect: isRedirect)
            guard isRedirect, let query else { return }
            if let continuation {
                self.continuation = nil
                continuation.resume(returning: query)
            } else {
                self.pending = query
            }
        }
    }

    private static func respond(on connection: NWConnection, success: Bool, isRedirect: Bool) {
        let (title, detail) = !isRedirect ? ("", "") : success
            ? ("Gmail is connected", "New mail now slides out of your notch. You can close this tab.")
            : ("Sign-in didn't finish", "Close this tab and choose Connect Gmail… in the Notch Mail menu-bar icon to try again.")
        let html = """
        <html><head><meta charset="utf-8"><title>Notch Mail</title></head>
        <body style="font:16px -apple-system,sans-serif;display:flex;align-items:center;justify-content:center;\
        height:90vh;margin:0;background:#111;color:#eee;text-align:center">
        <div>
        <h2 style="margin:12px 0 6px">\(title)</h2><p style="color:#aaa;margin:0">\(detail)</p></div>
        </body></html>
        """
        let response = "HTTP/1.1 \(isRedirect ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    /// Query parameters from the first line of an HTTP request ("GET /?a=b HTTP/1.1").
    static func queryItems(fromRequest request: String) -> [String: String]? {
        let line = request.split(separator: "\r\n", maxSplits: 1).first ?? ""
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let components = URLComponents(string: "http://127.0.0.1" + parts[1]),
              components.path.isEmpty || components.path == "/" else { return nil }
        let items = components.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }
}
