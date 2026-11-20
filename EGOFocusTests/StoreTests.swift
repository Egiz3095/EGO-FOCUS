import XCTest
import SwiftData
@testable import EGOFocus

@MainActor
final class StoreTests: XCTestCase {
    var store: TaskStore!

    override func setUp() async throws {
        let container = try Persistence.makeInMemoryContainer()
        store = TaskStore(container: container, syncsNotifications: false)
        store.clock = { TestClock.now }
    }

    private func draft(_ title: String, _ date: Date, recurrence: TaskRecurrence = .none) -> TaskDraft {
        var d = TaskDraft(dueDate: date, reminderOffsets: [0])
        d.title = title
        d.recurrence = recurrence
        return d
    }

    func testCreateEditDelete() throws {
        let task = try XCTUnwrap(store.add(draft("  مهمة  ", TestClock.date(2026, 11, 21, 12))))
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(task.title, "مهمة", "Title is trimmed")

        var edit = TaskDraft(task: task)
        edit.title = "مهمة معدلة"
        edit.details = "وصف"
        edit.notes = "ملاحظة"
        edit.priority = .urgent
        edit.category = .finance
        store.update(task, with: edit)
        XCTAssertEqual(store.tasks.first?.title, "مهمة معدلة")
        XCTAssertEqual(store.tasks.first?.priority, .urgent)
        XCTAssertEqual(store.tasks.first?.details, "وصف")

        store.delete(task)
        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testEmptyTitleIsRejected() {
        XCTAssertNil(store.add(draft("   ", TestClock.now)))
        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testCompleteAndReopen() throws {
        let task = try XCTUnwrap(store.add(draft("أ", TestClock.date(2026, 11, 21, 12))))
        store.toggleCompletion(task)
        XCTAssertTrue(task.isCompleted)
        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(store.stats(for: .day).completed, 1)
        XCTAssertEqual(store.completedTasks.count, 1)

        store.toggleCompletion(task)
        XCTAssertFalse(task.isCompleted)
        XCTAssertEqual(store.events.count, 0, "Reopening removes the completion record")
        XCTAssertEqual(store.stats(for: .day).completed, 0)
    }

    func testRecurringCompletionAdvancesWithoutDuplicates() throws {
        let task = try XCTUnwrap(store.add(draft("يومية", TestClock.date(2026, 11, 21, 9), recurrence: .daily)))
        store.toggleCompletion(task)
        XCTAssertEqual(store.tasks.count, 1, "No duplicate task is created")
        XCTAssertFalse(task.isCompleted)
        XCTAssertEqual(task.dueDate, TestClock.date(2026, 11, 22, 9))
        XCTAssertEqual(store.events.count, 1)
    }

    func testMonthlyAnchorIsKept() throws {
        let task = try XCTUnwrap(store.add(draft("قسط", TestClock.date(2026, 12, 31, 9), recurrence: .monthly)))
        XCTAssertEqual(task.recurrenceAnchorDay, 31)
        store.clock = { TestClock.date(2027, 1, 1, 8) }
        store.toggleCompletion(task) // → 31 Jan
        XCTAssertEqual(task.dueDate, TestClock.date(2027, 1, 31, 9))
        store.clock = { TestClock.date(2027, 2, 1, 8) }
        store.toggleCompletion(task) // → 28 Feb
        XCTAssertEqual(task.dueDate, TestClock.date(2027, 2, 28, 9))
        store.clock = { TestClock.date(2027, 3, 1, 8) }
        store.toggleCompletion(task) // → 31 Mar
        XCTAssertEqual(task.dueDate, TestClock.date(2027, 3, 31, 9))
    }

    func testDeleteCascadesStatistics() throws {
        let task = try XCTUnwrap(store.add(draft("ب", TestClock.date(2026, 11, 21, 7))))
        store.toggleCompletion(task)
        XCTAssertEqual(store.stats(for: .week).completed, 1)
        store.delete(task)
        XCTAssertEqual(store.events.count, 0, "Completion events are deleted with the task")
        XCTAssertEqual(store.stats(for: .week).completed, 0)
    }

    func testSectionsDoNotOverlap() throws {
        store.add(draft("متأخرة", TestClock.date(2026, 11, 20, 9)))
        store.add(draft("فات وقتها اليوم", TestClock.date(2026, 11, 21, 7)))
        store.add(draft("اليوم", TestClock.date(2026, 11, 21, 18)))
        store.add(draft("غداً", TestClock.date(2026, 11, 22, 9)))
        XCTAssertEqual(store.overdue.map(\.title), ["متأخرة", "فات وقتها اليوم"])
        XCTAssertEqual(store.todayOpen.map(\.title), ["اليوم"])
        XCTAssertEqual(store.upcoming.map(\.title), ["غداً"])

        let day = store.stats(for: .day)
        XCTAssertEqual(day.overdue, 1)
        XCTAssertEqual(day.pending, 1)
        XCTAssertEqual(day.total, 2)
    }

    func testCalendarProjectsRecurringTasks() throws {
        store.add(draft("أسبوعية", TestClock.date(2026, 11, 21, 9), recurrence: .weekly))
        XCTAssertEqual(store.items(on: TestClock.date(2026, 11, 28)).count, 1)
        XCTAssertTrue(store.items(on: TestClock.date(2026, 11, 28)).first!.isProjection)
        XCTAssertTrue(store.items(on: TestClock.date(2026, 11, 27)).isEmpty)
    }

    func testCompletionRate() throws {
        let a = try XCTUnwrap(store.add(draft("1", TestClock.date(2026, 11, 21, 10))))
        store.add(draft("2", TestClock.date(2026, 11, 21, 11)))
        store.toggleCompletion(a)
        XCTAssertEqual(store.stats(for: .day).completionRate, 0.5, accuracy: 0.0001)
    }
}
