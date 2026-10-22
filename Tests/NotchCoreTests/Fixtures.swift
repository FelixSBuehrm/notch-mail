import Foundation
@testable import NotchCore

enum Fixtures {
    static let work = MailAccount(id: "work", name: "Work", address: "alex@example.com")

    static func message(_ id: String, subject: String = "Hello") -> MailMessage {
        MailMessage(
            id: id,
            account: work,
            senderName: "Anna Weber",
            senderAddress: "anna@example.com",
            subject: subject,
            body: "Short body for \(id).",
            receivedAt: Date(timeIntervalSince1970: 1_000_000)
        )
    }
}
