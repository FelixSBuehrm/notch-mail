import Foundation
import NotchCore

/// Fake mail for step 1, so the notch can be judged before any account is connected.
/// Replies and actions go nowhere.
@MainActor
final class DemoMailSource {
    private let deliver: @MainActor (MailMessage) -> Void
    private let remove: @MainActor (Set<MailMessage.ID>) -> Void
    private var sent = 0
    private var pending: [Task<Void, Never>] = []
    private var loop: Task<Void, Never>?

    static let interval: Duration = .seconds(20)

    init(
        deliver: @escaping @MainActor (MailMessage) -> Void,
        remove: @escaping @MainActor (Set<MailMessage.ID>) -> Void
    ) {
        self.deliver = deliver
        self.remove = remove
    }

    /// Every sample once, with staggered ages (newest first), for the scripted tour.
    static func tourMessages(now: Date = .now) -> [MailMessage] {
        let ages: [TimeInterval] = [120, 30, 900, 2_400, 5_400, 9_000, 14_000, 20_000]
        return samples.enumerated().map { index, sample in
            sample.message(id: "demo-tour-\(index)", at: now.addingTimeInterval(-ages[index % ages.count]))
        }
    }

    static func isDemo(_ message: MailMessage) -> Bool {
        message.id.hasPrefix("demo-")
    }

    /// Takes all demo mail out of the notch, e.g. once a real account is connected.
    func clear() {
        isAutomatic = false
        pending.forEach { $0.cancel() }
        pending = []
        guard sent > 0 else { return }
        remove(Set((1...sent).map { "demo-\($0)" }))
    }

    var isAutomatic = false {
        didSet {
            loop?.cancel()
            loop = isAutomatic ? Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.interval)
                    guard !Task.isCancelled else { return }
                    self?.sendOne()
                }
            } : nil
        }
    }

    func sendOne(after delay: Duration = .zero) {
        pending.append(Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            let sample = Self.samples[sent % Self.samples.count]
            sent += 1
            deliver(sample.message(id: "demo-\(sent)", at: .now))
        })
    }
}

private struct Sample {
    let account: MailAccount
    let name: String
    let address: String
    let subject: String
    let body: String
    var html: String?

    func message(id: String, at date: Date) -> MailMessage {
        MailMessage(
            id: id, account: account, senderName: name, senderAddress: address,
            subject: subject, body: body, html: html, receivedAt: date
        )
    }
}

private extension DemoMailSource {
    // Fictional people and example.* domains only.
    static let work = MailAccount(id: "work", name: "Work", address: "alex@example.com")
    static let personal = MailAccount(id: "private", name: "Private", address: "alex@example.org")

    static let samples: [Sample] = [
        Sample(
            account: work, name: "Acme Cloud", address: "updates@example.com",
            subject: "Your October usage report",
            body: "Your October usage report. Requests: 12,400. Spend: $18.20. View the dashboard: https://example.com/dashboard",
            html: """
            <html><body style="font-family:Helvetica,Arial,sans-serif">
            <img src="https://example.com/logo.png" alt="Acme" width="120">
            <h2 style="color:#222">Your October usage report</h2>
            <p>Hi Alex, here is how your workspace did this month.</p>
            <table style="border-collapse:collapse;width:100%">
              <tr><td style="padding:8px;border-bottom:1px solid #eee">Requests</td><td style="padding:8px;border-bottom:1px solid #eee;text-align:right"><b>12,400</b></td></tr>
              <tr><td style="padding:8px;border-bottom:1px solid #eee">Spend</td><td style="padding:8px;border-bottom:1px solid #eee;text-align:right"><b>$18.20</b></td></tr>
              <tr><td style="padding:8px">Change vs. September</td><td style="padding:8px;text-align:right;color:#1a7f37"><b>−12%</b></td></tr>
            </table>
            <p style="margin-top:20px"><a href="https://example.com/dashboard" style="background:#d97757;color:#fff;padding:10px 16px;border-radius:6px;text-decoration:none">Open the dashboard</a></p>
            <p style="color:#888;font-size:12px">You get this report once a month. <a href="https://example.com/settings">Change email settings</a></p>
            </body></html>
            """
        ),
        Sample(
            account: personal, name: "GitHub", address: "noreply@github.com",
            subject: "[GitHub] Please verify your device",
            body: """
            Hey alex!

            A sign in attempt requires further verification because we did not recognize your device.

            Verification code: 482913

            If you did not attempt to sign in to your account, your password may be compromised.
            """
        ),
        Sample(
            account: work, name: "Sam Rivera", address: "sam@example.com",
            subject: "Re: Roadmap review",
            body: """
            Works for me. I put the notes in the doc: \
            https://docs.example.com/document/d/1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789/edit?usp=sharing

            The new pricing page is live too <https://example.com/pricing?utm_source=mail&utm_campaign=q4>.

            Sam

            On Tue, Oct 21, 2026 at 3:14 PM Alex Morgan <
            alex@example.com> wrote:

            > Can we go through the roadmap on Thursday?
            >
            > Alex
            """
        ),
        Sample(
            account: work, name: "Priya Shah", address: "priya@example.com",
            subject: "Slides for Thursday",
            body: """
            Hi Alex,

            thanks for the quick turnaround on the draft. Two small comments on \
            slide 4 (the timeline) and the budget summary. Nothing structural.

            Could you confirm by Friday whether the shorter version works for you? \
            Then I'll send the final deck on Monday.

            Best,
            Priya
            """
        ),
        Sample(
            account: personal, name: "Bike Workshop", address: "hello@example.net",
            subject: "Your repair is ready",
            body: """
            Hello Alex,

            your bike is ready for pickup. We replaced the chain and adjusted the rear brake. \
            We're open Saturday 10:00–16:00 and Monday from 9:00.

            See you soon!
            """
        ),
        Sample(
            account: work, name: "GitHub", address: "notifications@github.com",
            subject: "[notch-mail] Review requested on #42",
            body: "Sam requested your review on pull request #42: Fold quoted replies in Outlook mails."
        ),
        Sample(
            account: personal, name: "Paketdienst", address: "noreply@example.net",
            subject: "Ihr Paket kommt heute",
            body: "Ihre Sendung 0034 1234 5678 wird heute zwischen 14:00 und 17:00 zugestellt."
        ),
        Sample(
            account: work, name: "Sam Rivera", address: "sam@example.com",
            subject: "Lunch Thursday?",
            body: "Hey, are you around on Thursday? Thought we could grab lunch and go through the roadmap."
        ),
    ]
}
