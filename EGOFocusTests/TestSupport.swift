import Foundation
@testable import EGOFocus

enum TestClock {
    static var calendar: Calendar { AppCalendar.calendar }

    /// Saturday 21 November 2026, 08:00 local time.
    static var now: Date { date(2026, 11, 21, 8, 0) }

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min; c.second = 0
        return calendar.date(from: c)!
    }

    static func parts(_ date: Date) -> (y: Int, m: Int, d: Int, h: Int, min: Int) {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return (c.year!, c.month!, c.day!, c.hour!, c.minute!)
    }
}
