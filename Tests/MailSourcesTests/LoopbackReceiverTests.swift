import Foundation
import Testing
@testable import MailSources

@Suite("Loopback receiver (real socket on 127.0.0.1)")
struct LoopbackReceiverTests {
    @Test func catchesTheRedirectAndIgnoresTheFavicon() async throws {
        let receiver = try LoopbackReceiver(expectedState: "s1")
        let redirect = try await receiver.start()
        #expect(redirect.host == "127.0.0.1")
        #expect((redirect.port ?? 0) > 0)

        async let query = receiver.waitForRedirect(timeout: .seconds(10))
        let (_, favicon) = try await URLSession.shared.data(from: redirect.appending(path: "favicon.ico"))
        let (page, response) = try await URLSession.shared.data(from: URL(string: "\(redirect)/?code=4%2Fabc&state=s1")!)

        #expect((favicon as? HTTPURLResponse)?.statusCode == 404)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: page, as: UTF8.self).contains("connected"))
        let result = try await query
        #expect(result["code"] == "4/abc")
    }

    @Test func requestsWithTheWrongStateCannotAbortTheSignIn() async throws {
        let receiver = try LoopbackReceiver(expectedState: "right")
        let redirect = try await receiver.start()
        async let query = receiver.waitForRedirect(timeout: .seconds(10))

        // Another local program guesses the port and sends junk.
        let (_, junk) = try await URLSession.shared.data(from: URL(string: "\(redirect)/?error=x&state=wrong")!)
        let (_, other) = try await URLSession.shared.data(from: URL(string: "\(redirect)/elsewhere?code=c&state=right")!)
        _ = try await URLSession.shared.data(from: URL(string: "\(redirect)/?code=real&state=right")!)

        #expect((junk as? HTTPURLResponse)?.statusCode == 404)
        #expect((other as? HTTPURLResponse)?.statusCode == 404)
        #expect(try await query["code"] == "real")
    }

    @Test func aRedirectBeforeWaitingIsNotLost() async throws {
        let receiver = try LoopbackReceiver(expectedState: "s")
        let redirect = try await receiver.start()

        _ = try await URLSession.shared.data(from: URL(string: "\(redirect)/?code=early&state=s")!)
        let result = try await receiver.waitForRedirect(timeout: .seconds(10))

        #expect(result["code"] == "early")
    }

    @Test func timesOut() async throws {
        let receiver = try LoopbackReceiver(expectedState: "s")
        _ = try await receiver.start()

        await #expect(throws: MailSourceError.self) {
            try await receiver.waitForRedirect(timeout: .milliseconds(200))
        }
    }
}
