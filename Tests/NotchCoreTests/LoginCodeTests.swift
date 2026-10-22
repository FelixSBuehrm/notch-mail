import Testing
@testable import NotchCore

@Suite("Login codes")
struct LoginCodeTests {
    @Test(arguments: [
        ("Your verification code", "Verification code: 482913\n\nIf you didn't request this, ignore this email.", "482913"),
        ("G-582017 is your Google verification code", "Enter this code to finish signing in.", "582017"),
        ("Your Amazon one-time password", "Your one-time password (OTP) is 731 904. Don't share it.", "731904"),
        ("Microsoft account security code", "Please use the following security code for the account te***@example.com.\n\nSecurity code: 4458123", "4458123"),
        ("Slack confirmation code: Q7X-4KD", "Your confirmation code is below — enter it in your open browser window.\n\nQ7X-4KD", "Q7X-4KD"),
        ("Ihr Bestätigungscode", "Hallo, Ihr Bestätigungscode lautet 093847. Er ist 10 Minuten gültig.", "093847"),
        ("Sign in to Notion", "Here is your login code: 553-104", "553104"),
        ("Dein Anmeldecode für Revolut", "Code: 8812", "8812"),
    ])
    func findsCodes(subject: String, body: String, expected: String) {
        #expect(LoginCode.detect(subject: subject, body: body) == expected)
    }

    @Test(arguments: [
        ("Your order 112-4478123-5512 has shipped", "Order total: €49.00. Track your package: 0034 1234 5678 9012."),
        ("Lunch Thursday?", "Are you around on Thursday at 12:30? Call me on +1 555 010 4477."),
        ("Invoice 2026-1043", "Amount due 1250.00 CHF by 30.11.2026. Reference 778812."),
        ("Your October usage report", "Requests: 12,400. Spend: $18.20."),
        ("Meeting notes", "We discussed the code review for PR 4412 and the 2026 roadmap."),
        ("Ihr Paket kommt heute", "Ihre Sendung 0034 1234 5678 wird heute zwischen 14:00 und 17:00 zugestellt."),
    ])
    func ignoresNumbersThatAreNotCodes(subject: String, body: String) {
        #expect(LoginCode.detect(subject: subject, body: body) == nil)
    }

    @Test func messagesCarryTheirCode() {
        let message = MailMessage(
            id: "c", account: Fixtures.work, senderName: "GitHub", senderAddress: "noreply@github.com",
            subject: "[GitHub] Please verify your device", body: "Verification code: 381 022", receivedAt: .now
        )

        #expect(message.loginCode == "381022")
    }

    @Test func hugeBodiesStayCheap() {
        let body = String(repeating: "code 12 ", count: 200_000)
        let clock = ContinuousClock()

        let elapsed = clock.measure { _ = LoginCode.detect(subject: "x", body: body) }

        #expect(elapsed < .milliseconds(200))
    }
}
