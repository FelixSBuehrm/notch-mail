import AppKit
import MailSources
import NotchCore
import os

/// Connects mailboxes to the notch: checks them on a timer, turns changes into
/// notch events, and carries out actions and reminders.
///
/// Every `await` can outlive the account (disconnect, reconnect), so results
/// are only applied if the connection's `generation` is still the same.
@MainActor
final class MailCoordinator {
    struct Status {
        let account: MailAccount
        var lastChecked: Date?
        var error: String?
    }

    private struct Connection {
        let source: any MailSource
        /// What Claude may look up while drafting a reply for this account.
        let draftTools: any DraftTools
        let generation = UUID()
        var sync: InboxSync
        var failures = 0
        var nextAttempt = Date.distantPast
    }

    /// Login codes shouldn't keep you waiting; one list call every 10 s is cheap.
    static let pollInterval: Duration = .seconds(10)
    /// Longest wait between retries while offline or failing.
    static let maxBackoff: TimeInterval = 600
    static let gmail = "gmail"
    static let outlook = "outlook"

    private let log = Logger(subsystem: AppIdentity.bundleID, category: "mail")
    private let notch: NotchController
    private let transport = URLSessionTransport()
    private var connections: [String: Connection] = [:]
    private(set) var statuses: [String: Status] = [:]
    private(set) var isConnecting = false
    /// Outlook sign-in in progress; holds the code to type on Microsoft's page once it's known.
    private(set) var outlookSignIn: OutlookSignIn?

    enum OutlookSignIn: Equatable {
        case starting
        case waiting(code: String, url: URL)
    }
    private var isChecking = false
    private var recheckRequested = false
    private var pollLoop: Task<Void, Never>?
    private var reminderWakeups: [MailMessage.ID: Task<Void, Never>] = [:]

    /// Called whenever `statuses` or `isConnecting` change (the menu redraws).
    var onChange: (() -> Void)?
    /// Called after an account was connected through sign-in.
    var onConnected: (() -> Void)?
    var hasAccounts: Bool { !connections.isEmpty }

    func isConnected(_ key: String) -> Bool { connections[key] != nil }

    init(notch: NotchController) {
        self.notch = notch
    }

    // MARK: - Lifecycle

    func start() {
        if let address = AccountStore.gmailAddress {
            do {
                try attachGmail(address: address)
            } catch {
                log.error("Gmail restore failed: \(error.localizedDescription, privacy: .private)")
                statuses[Self.gmail] = Status(account: AccountStore.gmailAccount(address), error: describe(error))
            }
        }
        if let address = AccountStore.outlookAddress {
            do {
                try attachOutlook(address: address)
            } catch {
                log.error("Outlook restore failed: \(error.localizedDescription, privacy: .private)")
                statuses[Self.outlook] = Status(account: AccountStore.outlookAccount(address), error: describe(error))
            }
        }
        pollLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkNow()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func connectGmail() async {
        guard !isConnecting else { return }
        isConnecting = true
        onChange?()
        defer { isConnecting = false; onChange?() }
        do {
            let credentials = try AccountStore.googleCredentials()
            let token = try await GoogleSignIn.run(credentials: credentials, transport: transport) { url in
                Task { @MainActor [notch] in
                    notch.send(.notify("Continue in your browser"))
                    Browser.open(url)
                }
            }
            guard let address = token.email, let refresh = token.refreshToken else {
                throw MailSourceError.signInFailed("Google didn't say which account this is")
            }
            detach(Self.gmail)
            try AccountStore.saveGmail(address: address, refreshToken: refresh)
            try attachGmail(address: address)
            onConnected?()
            notch.send(.notify("Gmail connected"))
            await checkNow()
        } catch {
            log.error("Gmail sign-in failed: \(error.localizedDescription, privacy: .private)")
            notch.send(.notify("Gmail sign-in failed"))
            // Leave a working connection's status alone; just report the failed attempt.
            if connections[Self.gmail] == nil {
                let account = AccountStore.gmailAccount(AccountStore.gmailAddress ?? "Gmail")
                statuses[Self.gmail] = Status(account: account, error: describe(error))
            }
        }
    }

    func disconnectGmail() {
        detach(Self.gmail)
        statuses[Self.gmail] = nil
        if let address = AccountStore.gmailAddress { revokeAtGoogle(address) }
        do {
            try AccountStore.forgetGmail()
        } catch {
            log.error("Removing the Gmail sign-in failed: \(error.localizedDescription, privacy: .private)")
            notch.send(.notify("Couldn't remove the sign-in from the Keychain"))
        }
        onChange?()
    }

    // MARK: - Outlook / Hotmail

    /// Device-code sign-in: the code goes to the clipboard and Microsoft's page opens; paste, allow, done.
    func connectOutlook() async {
        guard outlookSignIn == nil else { return }
        outlookSignIn = .starting
        onChange?()
        defer { outlookSignIn = nil; onChange?() }
        do {
            let clientID = try AccountStore.microsoftClientID()
            let tokens = try await MicrosoftAuth.signIn(clientID: clientID, transport: transport) { code in
                await MainActor.run { [weak self] in
                    self?.outlookSignIn = .waiting(code: code.userCode, url: code.verificationURL)
                    self?.onChange?()
                    CodeClipboard.copy(code.userCode)
                    self?.notch.send(.notify("Code \(code.userCode) copied: paste it on Microsoft's page"))
                    Browser.open(code.verificationURL)
                }
            }
            // Uses the fresh access token, so the refresh token saved below stays the current one.
            let provider = MicrosoftTokenProvider(
                clientID: clientID, refreshToken: tokens.refreshToken, transport: transport,
                persist: { _ in }, current: (tokens.accessToken, tokens.expiresAt)
            )
            let address = try await OutlookSource.address(tokens: provider, transport: transport)
            detach(Self.outlook)
            try AccountStore.saveOutlook(address: address, refreshToken: tokens.refreshToken)
            try attachOutlook(address: address)
            onConnected?()
            notch.send(.notify("\(AccountStore.outlookAccount(address).name) connected"))
            await checkNow()
        } catch {
            log.error("Outlook sign-in failed: \(error.localizedDescription, privacy: .private)")
            notch.send(.notify("Outlook sign-in failed"))
            if connections[Self.outlook] == nil {
                let account = AccountStore.outlookAccount(AccountStore.outlookAddress ?? "Outlook")
                statuses[Self.outlook] = Status(account: account, error: describe(error))
            }
        }
    }

    func disconnectOutlook() {
        detach(Self.outlook)
        statuses[Self.outlook] = nil
        do {
            try AccountStore.forgetOutlook()
        } catch {
            log.error("Removing the Outlook sign-in failed: \(error.localizedDescription, privacy: .private)")
            notch.send(.notify("Couldn't remove the sign-in from the Keychain"))
        }
        onChange?()
    }

    private func attachOutlook(address: String) throws {
        let clientID = try AccountStore.microsoftClientID()
        guard let refresh = try AccountStore.outlookRefreshToken(for: address) else {
            throw MailSourceError.notConnected
        }
        let account = AccountStore.outlookAccount(address)
        // Microsoft hands out a new refresh token on every renewal; keep the latest.
        let tokens = MicrosoftTokenProvider(clientID: clientID, refreshToken: refresh, transport: transport) { [log] token in
            await MainActor.run {
                do {
                    try AccountStore.saveRenewedOutlookToken(token, for: address)
                } catch {
                    log.error("Saving the renewed Outlook sign-in failed: \(error.localizedDescription, privacy: .private)")
                }
            }
        }
        let outlook = OutlookSource(account: account, tokens: tokens, transport: transport)
        connections[Self.outlook] = Connection(
            source: outlook,
            draftTools: OutlookDraftTools(outlook: outlook),
            sync: InboxSync.empty.restoringReminders(AccountStore.reminders(for: account.id))
        )
        statuses[Self.outlook] = Status(account: account)
        onChange?()
    }

    private func attachGmail(address: String) throws {
        let credentials = try AccountStore.googleCredentials()
        guard let refresh = try AccountStore.gmailRefreshToken(for: address) else {
            throw MailSourceError.notConnected
        }
        let account = AccountStore.gmailAccount(address)
        let tokens = GoogleTokenProvider(credentials: credentials, refreshToken: refresh, transport: transport)
        let gmail = GmailSource(account: account, tokens: tokens, transport: transport)
        connections[Self.gmail] = Connection(
            source: gmail,
            draftTools: GoogleDraftTools(gmail: gmail, drive: DriveClient(tokens: tokens, transport: transport)),
            sync: InboxSync.empty.restoringReminders(AccountStore.reminders(for: account.id))
        )
        statuses[Self.gmail] = Status(account: account)
        onChange?()
    }

    /// Takes an account's mail out of the notch and forgets its in-memory state.
    private func detach(_ key: String) {
        guard let connection = connections.removeValue(forKey: key) else { return }
        let account = connection.source.account
        let shown = notch.state.unread.filter { $0.account == account }.map(\.id)
        if !shown.isEmpty { notch.send(.mailRemoved(Set(shown))) }
        for id in connection.sync.reminders.keys { reminderWakeups.removeValue(forKey: id)?.cancel() }
    }

    /// Best effort: makes the stored refresh token worthless at Google too.
    private func revokeAtGoogle(_ address: String) {
        let token: String?
        do {
            token = try AccountStore.gmailRefreshToken(for: address)
        } catch {
            log.error("Reading the token to revoke failed: \(error.localizedDescription, privacy: .private)")
            return
        }
        guard let token else { return }
        Task { [transport, log] in
            do {
                let (_, response) = try await transport.send(GoogleOAuth.revokeRequest(token: token))
                if response.statusCode != 200 { log.error("Revoke answered \(response.statusCode)") }
            } catch {
                log.error("Revoke failed: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    // MARK: - Checking

    /// `force`: from the menu or a due reminder; ignores the backoff.
    func checkNow(force: Bool = false) async {
        if force { for key in connections.keys { connections[key]?.nextAttempt = .distantPast } }
        guard !isChecking else {
            recheckRequested = true
            return
        }
        isChecking = true
        defer { isChecking = false }
        repeat {
            recheckRequested = false
            for key in connections.keys.sorted() { await check(key) }
        } while recheckRequested
        onChange?()
    }

    private func check(_ key: String) async {
        guard let connection = connections[key], Date() >= connection.nextAttempt else { return }
        let source = connection.source
        let generation = connection.generation
        do {
            let fetched = try await source.fetchUnread()
            guard isCurrent(key, generation) else { return }
            let changes = update(key) { $0.ingest(fetched, now: Date()) }
            if !changes.loaded.isEmpty { notch.send(.mailLoaded(changes.loaded)) }
            for message in changes.arrived { notch.send(.mailArrived(message)) }
            try await confirmMissing(changes.missing, key: key, source: source, generation: generation)
            try await announceDue(changes.due, key: key, source: source, generation: generation)
            guard isCurrent(key, generation) else { return }
            succeeded(key)
        } catch {
            guard isCurrent(key, generation) else { return }
            failed(key, error)
        }
        if let sync = connections[key]?.sync {
            AccountStore.saveReminders(sync.reminders, for: source.account.id)
        }
    }

    /// Mail no longer in the recent list: only removed once Gmail says it's read or gone.
    private func confirmMissing(_ missing: Set<MailMessage.ID>, key: String, source: any MailSource, generation: UUID) async throws {
        guard !missing.isEmpty else { return }
        let stillUnread = try await source.stillUnread(missing)
        guard isCurrent(key, generation) else { return }
        let gone = missing.subtracting(stillUnread)
        guard !gone.isEmpty, let sync = connections[key]?.sync else { return }
        connections[key]?.sync = sync.confirmingRemoved(gone)
        notch.send(.mailRemoved(gone))
    }

    /// A failure leaves the reminder in place, so the next check tries again.
    private func announceDue(_ due: [MailMessage.ID], key: String, source: any MailSource, generation: UUID) async throws {
        for id in due {
            let message = try await source.fetch(id: id)
            guard isCurrent(key, generation), let sync = connections[key]?.sync else { return }
            guard let message else {
                connections[key]?.sync = sync.droppingReminder(id)  // dealt with elsewhere
                continue
            }
            connections[key]?.sync = sync.announcing(id)
            notch.send(.mailArrived(message))
        }
    }

    private func succeeded(_ key: String) {
        connections[key]?.failures = 0
        connections[key]?.nextAttempt = .distantPast
        statuses[key]?.lastChecked = Date()
        statuses[key]?.error = nil
    }

    private func failed(_ key: String, _ error: Error) {
        log.error("Check failed for \(key, privacy: .public): \(error.localizedDescription, privacy: .private)")
        if case MailSourceError.authorizationRevoked = error {
            // Polling can't fix this; stop until the user connects again.
            detach(key)
            statuses[key]?.error = "Sign-in expired, connect again"
            notch.send(.notify("\(statuses[key]?.account.name ?? "Mail") sign-in expired"))
            return
        }
        let failures = (connections[key]?.failures ?? 0) + 1
        let wait = min(Self.maxBackoff, 20 * pow(2, Double(failures - 1)))
        connections[key]?.failures = failures
        connections[key]?.nextAttempt = Date().addingTimeInterval(wait)
        statuses[key]?.error = describe(error)
    }

    private func update(_ key: String, _ body: (InboxSync) -> (InboxSync, InboxChanges)) -> InboxChanges {
        guard let sync = connections[key]?.sync else {
            return .none
        }
        let (next, changes) = body(sync)
        connections[key]?.sync = next
        return changes
    }

    private func isCurrent(_ key: String, _ generation: UUID) -> Bool {
        connections[key]?.generation == generation
    }

    // MARK: - Actions

    func perform(_ action: MailAction, on message: MailMessage) {
        guard let (key, connection) = connection(for: message.account) else { return } // demo mail
        connections[key]?.sync = connection.sync.handling(message.id)
        Task {
            do {
                try await connection.source.perform(action, on: message.id)
            } catch {
                log.error("\(action.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .private)")
                guard isCurrent(key, connection.generation), let sync = connections[key]?.sync else { return }
                connections[key]?.sync = sync.unhandling(message.id)
                notch.send(.actionFailed(message, "Couldn't \(action.verb)"))
            }
        }
    }

    func remind(_ message: MailMessage, _ option: RemindOption) {
        let now = Date()
        let due = option.date(from: now)
        notch.send(.snoozed(message.id, confirmation: RemindOption.confirmation(for: due, now: now)))

        let real = connection(for: message.account)
        if let (key, connection) = real {
            let next = connection.sync.snoozing(message.id, until: due)
            connections[key]?.sync = next
            AccountStore.saveReminders(next.reminders, for: message.account.id)
        }
        // Check right when it's due rather than up to 20 s later. Demo mail just comes back.
        reminderWakeups[message.id]?.cancel()
        reminderWakeups[message.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, due.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            self.reminderWakeups[message.id] = nil
            if real == nil { self.notch.send(.mailArrived(message)) } else { await self.checkNow(force: true) }
        }
    }

    /// Drafting and sending for a message's account; demo mail gets a stand-in.
    func replyBackend(for message: MailMessage) -> any ReplyBackend {
        guard let (_, connection) = connection(for: message.account) else {
            return DemoMailSource.isDemo(message) ? DemoReplyBackend() : UnavailableReplyBackend()
        }
        return LiveReplyBackend(source: connection.source, tools: connection.draftTools, transport: transport)
    }

    private func connection(for account: MailAccount) -> (String, Connection)? {
        connections.first { $0.value.source.account == account }.map { ($0.key, $0.value) }
    }

    private func describe(_ error: Error) -> String {
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet { return "Offline" }
        return error.localizedDescription
    }
}

private extension MailAction {
    var verb: String {
        switch self {
        case .archive: "archive"
        case .delete: "delete"
        case .markRead: "mark as read"
        }
    }
}
