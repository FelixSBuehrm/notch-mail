import Foundation

/// One connected mailbox, e.g. work Gmail or private Hotmail.
public struct MailAccount: Hashable, Sendable {
    public let id: String
    /// Short label shown in the notch ("Work", "Private").
    public let name: String
    public let address: String

    public init(id: String, name: String, address: String) {
        self.id = id
        self.name = name
        self.address = address
    }
}

/// An unread message as the notch shows it. Immutable; the notch never edits mail.
public struct MailMessage: Identifiable, Hashable, Sendable {
    public typealias ID = String

    public let id: ID
    public let account: MailAccount
    public let senderName: String
    public let senderAddress: String
    public let subject: String
    /// Plain text: what previews, search and Claude use.
    public let body: String
    /// The original HTML, when the mail has one; shown with its own layout.
    public let html: String?
    public let receivedAt: Date
    /// A one-time login code found in the mail, if it is a code mail.
    public let loginCode: String?

    public init(
        id: ID,
        account: MailAccount,
        senderName: String,
        senderAddress: String,
        subject: String,
        body: String,
        html: String? = nil,
        receivedAt: Date
    ) {
        self.id = id
        self.account = account
        self.senderName = senderName
        self.senderAddress = senderAddress
        self.subject = subject
        self.body = body
        self.html = html
        self.receivedAt = receivedAt
        self.loginCode = LoginCode.detect(subject: subject, body: body)
    }
}

/// What the user can do to a message from the notch.
public enum MailAction: String, CaseIterable, Sendable {
    case archive
    case delete
    case markRead

    /// Text the notch shows briefly after the action.
    public var confirmation: String {
        switch self {
        case .archive: "Archived"
        case .delete: "Deleted"
        case .markRead: "Marked as read"
        }
    }
}
