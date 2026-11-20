import XCTest
@testable import EGOFocus

final class ParserTests: XCTestCase {
    private func parse(_ text: String) -> ParsedTask {
        NaturalLanguageTaskParser.parse(text, now: TestClock.now, calendar: TestClock.calendar, defaultReminderOffsets: [15])
    }

    private func assertDate(_ date: Date, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int,
                            file: StaticString = #filePath, line: UInt = #line) {
        let p = TestClock.parts(date)
        XCTAssertEqual([p.y, p.m, p.d, p.h, p.min], [y, m, d, h, min], file: file, line: line)
    }

    // MARK: The four commands from the specification

    func testRemindBillsTomorrowAtTenMorning() {
        let r = parse("ذكرني بمراجعة الفواتير بكرة الساعة 10 صباحاً")
        XCTAssertEqual(r.title, "مراجعة الفواتير")
        assertDate(r.date, 2026, 11, 22, 10, 0)
        XCTAssertTrue(r.dateDetected)
        XCTAssertTrue(r.timeDetected)
        XCTAssertEqual(r.reminderOffsets, [0])
        XCTAssertFalse(r.needsClarification, "\(r.issues)")
    }

    func testAddTaskOnSunday() {
        let r = parse("أضف مهمة شراء مستلزمات المكتب يوم الأحد")
        XCTAssertEqual(r.title, "شراء مستلزمات المكتب")
        let p = TestClock.parts(r.date)
        XCTAssertEqual([p.y, p.m, p.d], [2026, 11, 22]) // next Sunday
        XCTAssertTrue(r.dateDetected)
        XCTAssertFalse(r.timeDetected)
        XCTAssertTrue(r.needsClarification, "No time given: must ask the user to confirm")
        XCTAssertEqual(r.reminderOffsets, [15], "Uses the default reminder when no reminder verb is used")
    }

    func testMeetingTomorrowAtThreeAfternoon() {
        let r = parse("عندي اجتماع غداً الساعة 3 عصراً")
        XCTAssertEqual(r.title, "اجتماع")
        assertDate(r.date, 2026, 11, 22, 15, 0)
        XCTAssertFalse(r.needsClarification, "\(r.issues)")
    }

    func testRentOnFirstOfMonth() {
        let r = parse("ذكرني بدفع الإيجار يوم 1 من الشهر")
        XCTAssertEqual(r.title, "دفع الإيجار")
        let p = TestClock.parts(r.date)
        XCTAssertEqual([p.y, p.m, p.d], [2026, 12, 1], "1 November has passed → 1 December")
        XCTAssertTrue(r.dateDetected)
        XCTAssertFalse(r.timeDetected)
        XCTAssertTrue(r.needsClarification)
        XCTAssertFalse(r.hints.isEmpty, "Suggests monthly recurrence")
    }

    // MARK: More phrasing

    func testArabicIndicDigitsAndMinutes() {
        let r = parse("اجتماع العملاء بكرة الساعة ١٠:٣٠ صباحا")
        XCTAssertEqual(r.title, "اجتماع العملاء")
        assertDate(r.date, 2026, 11, 22, 10, 30)
    }

    func testHalfPastWithPeriodWord() {
        let r = parse("مكالمة المورد بكرة الساعة 3 ونص العصر")
        assertDate(r.date, 2026, 11, 22, 15, 30)
        XCTAssertEqual(r.title, "مكالمة المورد")
    }

    func testQuarterTo() {
        let r = parse("العشاء بكرة الساعة 9 الا ربع مساء")
        assertDate(r.date, 2026, 11, 22, 20, 45)
    }

    func testLunchIsNotTomorrow() {
        let r = parse("موعد الغداء الساعة 1 الظهر")
        XCTAssertEqual(r.title, "موعد الغداء")
        assertDate(r.date, 2026, 11, 21, 13, 0)
    }

    func testRelativeHour() {
        let r = parse("اتصل بالعميل بعد ساعة")
        XCTAssertEqual(r.title, "اتصل بالعميل")
        XCTAssertEqual(r.date, TestClock.now.addingTimeInterval(3600))
        XCTAssertFalse(r.needsClarification)
    }

    func testDailyRecurrence() {
        let r = parse("تمرين كل يوم الساعة 6 صباحا")
        XCTAssertEqual(r.recurrence, .daily)
        XCTAssertEqual(r.title, "تمرين")
        assertDate(r.date, 2026, 11, 22, 6, 0) // 06:00 today already passed
    }

    func testWeeklyOnWeekday() {
        let r = parse("اجتماع الفريق كل اثنين الساعة 9 صباحا")
        XCTAssertEqual(r.recurrence, .weekly)
        assertDate(r.date, 2026, 11, 23, 9, 0)
    }

    func testAmbiguousHourIsFlagged() {
        let r = parse("اجتماع الساعة 4")
        assertDate(r.date, 2026, 11, 21, 16, 0)
        XCTAssertTrue(r.needsClarification)
    }

    func testNoDateIsNotSilentlyAccepted() {
        let r = parse("شراء هدية")
        XCTAssertEqual(r.title, "شراء هدية")
        XCTAssertFalse(r.dateDetected)
        XCTAssertTrue(r.needsClarification)
    }

    func testReminderOffsetPhrase() {
        let r = parse("ذكرني قبلها بساعة باجتماع المجلس يوم الخميس الساعة 11 صباحا")
        XCTAssertEqual(r.title, "اجتماع المجلس")
        XCTAssertEqual(r.reminderOffsets, [60])
        assertDate(r.date, 2026, 11, 26, 11, 0)
    }

    func testExplicitNumericDate() {
        let r = parse("ادفع فاتورة الكهرباء 15/12")
        XCTAssertEqual(r.title, "ادفع فاتورة الكهرباء")
        let p = TestClock.parts(r.date)
        XCTAssertEqual([p.y, p.m, p.d], [2026, 12, 15])
        XCTAssertTrue(r.needsClarification)
    }

    func testMonthlyOn31st() {
        let r = parse("دفع القسط يوم 31 من كل شهر الساعة 9 صباحا")
        XCTAssertEqual(r.recurrence, .monthly)
        XCTAssertEqual(r.title, "دفع القسط")
        assertDate(r.date, 2026, 12, 31, 9, 0) // November has 30 days
        XCTAssertFalse(r.hints.isEmpty)
    }

    func testEgyptianToday() {
        let r = parse("مراجعة التقرير النهارده الساعة 5 مساء")
        XCTAssertEqual(r.title, "مراجعة التقرير")
        assertDate(r.date, 2026, 11, 21, 17, 0)
    }

    func testDayAfterTomorrow() {
        let r = parse("زيارة الوالدة بعد بكرة الساعة 7 مساء")
        XCTAssertEqual(r.title, "زيارة الوالدة")
        assertDate(r.date, 2026, 11, 23, 19, 0)
    }

    func testPastTimeTodayIsFlagged() {
        let r = parse("اجتماع اليوم الساعة 7 صباحا")
        XCTAssertTrue(r.needsClarification)
    }
}
