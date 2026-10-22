import Foundation

/// "Remind me" choices. The message leaves the notch and pops up again then.
public enum RemindOption: String, CaseIterable, Sendable {
    case inOneHour
    case thisEvening
    case tomorrowMorning

    static let eveningHour = 18
    static let morningHour = 8
    /// After this, "this evening" is too close to be worth offering.
    static let eveningCutoffHour = 17

    public var title: String {
        switch self {
        case .inOneHour: "In 1 hour"
        case .thisEvening: "This evening"
        case .tomorrowMorning: "Tomorrow morning"
        }
    }

    public func isAvailable(at now: Date, calendar: Calendar = .current) -> Bool {
        guard self == .thisEvening else { return true }
        return calendar.component(.hour, from: now) < Self.eveningCutoffHour
    }

    public func date(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .inOneHour:
            return now.addingTimeInterval(3_600)
        case .thisEvening:
            return calendar.date(bySettingHour: Self.eveningHour, minute: 0, second: 0, of: now) ?? now
        case .tomorrowMorning:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: Self.morningHour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        }
    }

    /// "Back at 18:00" / "Back tomorrow 08:00".
    public static func confirmation(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = String(
            format: "%02d:%02d",
            calendar.component(.hour, from: date),
            calendar.component(.minute, from: date)
        )
        if calendar.isDate(date, inSameDayAs: now) { return "Back at \(time)" }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        if calendar.isDate(date, inSameDayAs: tomorrow) { return "Back tomorrow \(time)" }
        return "Back later"
    }
}
