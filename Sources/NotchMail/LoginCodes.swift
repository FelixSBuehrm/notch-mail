import AppKit
import NotchCore

/// A login code seen in the last few minutes, for the menu-bar list.
struct RecentCode: Identifiable, Equatable {
    let id: MailMessage.ID
    let code: String
    let sender: String
    let receivedAt: Date
}

/// Codes from recent mail, kept in memory only and forgotten after 15 minutes.
struct RecentCodes {
    static let lifetime: TimeInterval = 15 * 60
    private(set) var all: [RecentCode] = []

    func current(at now: Date = Date()) -> [RecentCode] {
        all.filter { now.timeIntervalSince($0.receivedAt) < Self.lifetime }
    }

    mutating func record(_ messages: [MailMessage], at now: Date = Date()) {
        for message in messages {
            guard let code = message.loginCode, now.timeIntervalSince(message.receivedAt) < Self.lifetime,
                  !all.contains(where: { $0.id == message.id }) else { continue }
            all.append(RecentCode(id: message.id, code: code, sender: message.senderName, receivedAt: message.receivedAt))
        }
        all = current(at: now).sorted { $0.receivedAt > $1.receivedAt }
    }
}

/// Puts a code on the clipboard, marked so clipboard managers don't keep it,
/// and takes it off again after a while if nothing else was copied since.
@MainActor
enum CodeClipboard {
    static let clearAfter: Duration = .seconds(90)

    static func copy(_ code: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(code, forType: .string)
        board.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        let count = board.changeCount
        Task {
            try? await Task.sleep(for: clearAfter)
            if board.changeCount == count { board.clearContents() }
        }
    }
}
