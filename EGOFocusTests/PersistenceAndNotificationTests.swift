import XCTest
import SwiftData
import UserNotifications
@testable import EGOFocus

@MainActor
final class PersistenceTests: XCTestCase {
    func testDataSurvivesReopeningTheStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("test.store")
        defer { try? FileManager.default.removeItem(at: dir) }

        let id: UUID
        do {
            let container = try Persistence.makeContainer(storeURL: url)
            let store = TaskStore(container: container, syncsNotifications: false)
            var draft = TaskDraft(dueDate: TestClock.date(2026, 12, 1, 9), reminderOffsets: [15, 60])
            draft.title = "مهمة محفوظة"
            draft.recurrence = .monthly
            let task = try XCTUnwrap(store.add(draft))
            store.toggleCompletion(task)
            id = task.id
        }

        // A brand-new container on the same file = app relaunch.
        let reopened = try Persistence.makeContainer(storeURL: url)
        let store = TaskStore(container: reopened, syncsNotifications: false)
        XCTAssertEqual(store.tasks.count, 1)
        let task = try XCTUnwrap(store.task(id: id))
        XCTAssertEqual(task.title, "مهمة محفوظة")
        XCTAssertEqual(task.reminderOffsets, [15, 60])
        XCTAssertEqual(task.recurrence, .monthly)
        XCTAssertEqual(store.events.count, 1)
    }
}

final class ReminderPlannerTests: XCTestCase {
    let now = TestClock.now
    let cal = TestClock.calendar

    func makeTask(_ due: Date, offsets: [Int], recurrence: TaskRecurrence = .none, completed: Bool = false) -> TaskRecord {
        TaskRecord(title: "t", dueDate: due, isCompleted: completed, recurrence: recurrence, reminderOffsets: offsets)
    }

    func testOffsetsProduceOneRequestEach() {
        let task = makeTask(TestClock.date(2026, 11, 22, 10), offsets: [0, 15, 30, 60, 1440])
        let plan = ReminderPlanner.plan(tasks: [task], now: now, calendar: cal)
        XCTAssertEqual(plan.count, 5)
        XCTAssertEqual(Set(plan.map(\.identifier)).count, 5, "Unique identifiers")
        XCTAssertEqual(plan.first?.fireDate, TestClock.date(2026, 11, 21, 10), "1 day before")
        XCTAssertEqual(plan.last?.fireDate, TestClock.date(2026, 11, 22, 10), "At the due time")
    }

    func testPastFireTimesAndCompletedTasksAreSkipped() {
        let soon = makeTask(now.addingTimeInterval(600), offsets: [0, 15])
        let done = makeTask(TestClock.date(2026, 11, 22, 10), offsets: [0], completed: true)
        let none = makeTask(TestClock.date(2026, 11, 22, 10), offsets: [])
        let plan = ReminderPlanner.plan(tasks: [soon, done, none], now: now, calendar: cal)
        XCTAssertEqual(plan.map(\.identifier), [ReminderPlanner.identifier(taskID: soon.id, offset: 0)])
    }

    func testOverdueRecurringTaskRemindsForNextOccurrence() {
        let task = makeTask(TestClock.date(2026, 11, 19, 7), offsets: [0], recurrence: .daily)
        let plan = ReminderPlanner.plan(tasks: [task], now: now, calendar: cal)
        XCTAssertEqual(plan.first?.fireDate, TestClock.date(2026, 11, 22, 7))
    }

    func testRepeatedPlanningIsStable() {
        let task = makeTask(TestClock.date(2026, 11, 22, 10), offsets: [0, 60])
        XCTAssertEqual(ReminderPlanner.plan(tasks: [task], now: now, calendar: cal),
                       ReminderPlanner.plan(tasks: [task], now: now, calendar: cal))
    }

    func testRespectsSystemLimit() {
        let tasks = (0..<100).map { makeTask(now.addingTimeInterval(Double($0 + 1) * 3600), offsets: [0]) }
        let plan = ReminderPlanner.plan(tasks: tasks, now: now, calendar: cal)
        XCTAssertEqual(plan.count, ReminderPlanner.maxTaskRequests)
        XCTAssertEqual(plan.first?.taskID, tasks.first?.id, "Keeps the soonest reminders")
    }

    func testIdentifierParsing() {
        let id = UUID()
        XCTAssertEqual(NotificationService.taskID(fromIdentifier: "task.\(id.uuidString).15"), id.uuidString)
        XCTAssertEqual(NotificationService.taskID(fromIdentifier: "snooze.\(id.uuidString).123"), id.uuidString)
        XCTAssertNil(NotificationService.taskID(fromIdentifier: "daily.brief"))
    }
}

@MainActor
final class NotificationActionTests: XCTestCase {
    func testMarkDoneActionCompletesTask() async throws {
        let container = try Persistence.makeInMemoryContainer()
        let store = TaskStore(container: container, syncsNotifications: false)
        var draft = TaskDraft(dueDate: Date().addingTimeInterval(3600), reminderOffsets: [0])
        draft.title = "من الإشعار"
        let task = try XCTUnwrap(store.add(draft))

        await NotificationService.shared.handle(action: NotificationService.doneAction,
                                                taskIDString: task.id.uuidString,
                                                title: task.title,
                                                context: container.mainContext)
        store.refresh()
        XCTAssertTrue(task.isCompleted)
        XCTAssertEqual(store.events.count, 1)
    }

    func testMarkDoneOnRecurringTaskMovesToNextOccurrence() async throws {
        let container = try Persistence.makeInMemoryContainer()
        let store = TaskStore(container: container, syncsNotifications: false)
        let due = Date().addingTimeInterval(1800)
        var draft = TaskDraft(dueDate: due, reminderOffsets: [0])
        draft.title = "متكررة"
        draft.recurrence = .daily
        let task = try XCTUnwrap(store.add(draft))
        let before = task.dueDate

        await NotificationService.shared.handle(action: NotificationService.doneAction,
                                                taskIDString: task.id.uuidString, title: task.title,
                                                context: container.mainContext)
        XCTAssertFalse(task.isCompleted)
        XCTAssertGreaterThan(task.dueDate, before)
        XCTAssertEqual(store.tasks.count, 1)
    }

    func testSnoozeSchedulesTenMinuteReminder() async throws {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        try XCTSkipUnless(status == .authorized, "Notification permission not granted in this simulator run")
        let id = UUID()
        await NotificationService.shared.handle(action: NotificationService.snoozeAction,
                                                taskIDString: id.uuidString, title: "تأجيل")
        let pending = await center.pendingNotificationRequests()
        let snoozed = try XCTUnwrap(pending.first { $0.identifier.hasPrefix("snooze.\(id.uuidString)") })
        let trigger = try XCTUnwrap(snoozed.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, 600)
        center.removePendingNotificationRequests(withIdentifiers: [snoozed.identifier])
    }
}
