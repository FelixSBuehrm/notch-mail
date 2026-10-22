import Foundation
import Testing
@testable import NotchCore

@Suite("Remind me")
struct RemindOptionTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func inOneHour() {
        #expect(RemindOption.inOneHour.date(from: date(22, 10), calendar: calendar) == date(22, 11))
    }

    @Test func thisEveningIsSixPmToday() {
        #expect(RemindOption.thisEvening.date(from: date(22, 10), calendar: calendar) == date(22, 18))
    }

    @Test func thisEveningIsOfferedOnlyBeforeFivePm() {
        #expect(RemindOption.thisEvening.isAvailable(at: date(22, 16, 59), calendar: calendar))
        #expect(!RemindOption.thisEvening.isAvailable(at: date(22, 17), calendar: calendar))
        #expect(RemindOption.inOneHour.isAvailable(at: date(22, 23), calendar: calendar))
    }

    @Test func tomorrowMorningIsEightAmNextDay() {
        #expect(RemindOption.tomorrowMorning.date(from: date(22, 23, 30), calendar: calendar) == date(23, 8))
    }

    @Test func confirmationSaysWhenItComesBack() {
        let now = date(22, 10)

        #expect(RemindOption.confirmation(for: date(22, 18), now: now, calendar: calendar) == "Back at 18:00")
        #expect(RemindOption.confirmation(for: date(23, 8), now: now, calendar: calendar) == "Back tomorrow 08:00")
    }
}
