import XCTest
@testable import EGOFocus

final class RecurrenceTests: XCTestCase {
    let cal = TestClock.calendar

    func testDailyAndWeekly() {
        let start = TestClock.date(2026, 11, 21, 9, 30)
        let daily = RecurrenceEngine.next(after: start, rule: .daily, anchorDay: 0, calendar: cal)
        XCTAssertEqual(daily, TestClock.date(2026, 11, 22, 9, 30))
        let weekly = RecurrenceEngine.next(after: start, rule: .weekly, anchorDay: 0, calendar: cal)
        XCTAssertEqual(weekly, TestClock.date(2026, 11, 28, 9, 30))
    }

    func testMonthly31stClampsThenReturns() {
        let jan31 = TestClock.date(2027, 1, 31, 10, 0)
        let feb = RecurrenceEngine.next(after: jan31, rule: .monthly, anchorDay: 31, calendar: cal)
        XCTAssertEqual(feb, TestClock.date(2027, 2, 28, 10, 0))
        let mar = RecurrenceEngine.next(after: feb, rule: .monthly, anchorDay: 31, calendar: cal)
        XCTAssertEqual(mar, TestClock.date(2027, 3, 31, 10, 0), "Returns to the 31st, no drift")
        let apr = RecurrenceEngine.next(after: mar, rule: .monthly, anchorDay: 31, calendar: cal)
        XCTAssertEqual(apr, TestClock.date(2027, 4, 30, 10, 0))
    }

    func testMonthlyLeapYear() {
        let jan31 = TestClock.date(2028, 1, 31, 8, 0)
        let feb = RecurrenceEngine.next(after: jan31, rule: .monthly, anchorDay: 31, calendar: cal)
        XCTAssertEqual(feb, TestClock.date(2028, 2, 29, 8, 0))
    }

    func testMonthlyDecemberToJanuary() {
        let dec15 = TestClock.date(2026, 12, 15, 8, 0)
        let jan = RecurrenceEngine.next(after: dec15, rule: .monthly, anchorDay: 15, calendar: cal)
        XCTAssertEqual(jan, TestClock.date(2027, 1, 15, 8, 0))
    }

    func testNextOccurrenceSkipsMissedDays() {
        let threeDaysAgo = TestClock.date(2026, 11, 18, 7, 0)
        let next = RecurrenceEngine.nextOccurrence(from: threeDaysAgo, after: TestClock.now, rule: .daily,
                                                   anchorDay: 0, calendar: cal)
        XCTAssertEqual(next, TestClock.date(2026, 11, 22, 7, 0))
    }

    func testOccursOnProjection() {
        let start = TestClock.date(2027, 1, 31, 9, 0)
        XCTAssertTrue(RecurrenceEngine.occurs(on: TestClock.date(2027, 2, 28), start: start, rule: .monthly, anchorDay: 31, calendar: cal))
        XCTAssertFalse(RecurrenceEngine.occurs(on: TestClock.date(2027, 2, 27), start: start, rule: .monthly, anchorDay: 31, calendar: cal))
        XCTAssertFalse(RecurrenceEngine.occurs(on: TestClock.date(2027, 1, 30), start: start, rule: .daily, anchorDay: 0, calendar: cal),
                       "No occurrences before the series start")
        XCTAssertTrue(RecurrenceEngine.occurs(on: TestClock.date(2027, 2, 7), start: start, rule: .weekly, anchorDay: 0, calendar: cal))
    }
}
