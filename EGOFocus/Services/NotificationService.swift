import Foundation
import UserNotifications
import SwiftData

struct PlannedReminder: Equatable {
    let identifier: String
    let taskID: UUID
    let title: String
    let body: String
    let fireDate: Date
}

/// Pure planning of task reminders (unit tested). One request per (task, offset):
/// deterministic identifiers mean re-planning never produces duplicate notifications.
enum ReminderPlanner {
    /// iOS keeps at most 64 pending requests per app; leave room for the morning brief and snoozes.
    static let maxTaskRequests = 56

    static func identifier(taskID: UUID, offset: Int) -> String { "task.\(taskID.uuidString).\(offset)" }

    static func plan(tasks: [TaskRecord], now: Date, calendar: Calendar) -> [PlannedReminder] {
        var result: [PlannedReminder] = []
        for task in tasks where !task.isCompleted {
            let offsets = Set(task.reminderOffsets)
            guard !offsets.isEmpty else { continue }
            var occurrence = task.dueDate
            if task.recurrence != .none && occurrence <= now {
                // Overdue recurring task: keep reminding for the next occurrence of the series.
                occurrence = RecurrenceEngine.nextOccurrence(from: occurrence, after: now, rule: task.recurrence,
                                                             anchorDay: task.recurrenceAnchorDay, calendar: calendar)
            }
            for offset in offsets.sorted() {
                guard let fire = calendar.date(byAdding: .minute, value: -offset, to: occurrence), fire > now else { continue }
                result.append(PlannedReminder(identifier: identifier(taskID: task.id, offset: offset),
                                              taskID: task.id,
                                              title: task.title,
                                              body: body(title: task.title, offset: offset, due: occurrence),
                                              fireDate: fire))
            }
        }
        return Array(result.sorted { $0.fireDate < $1.fireDate }.prefix(maxTaskRequests))
    }

    static func body(title: String, offset: Int, due: Date) -> String {
        switch offset {
        case 0: return "حان الآن موعد: \(title)"
        case 1440: return "غداً الساعة \(AppFormat.time(due)): \(title)"
        default: return "بعد \(offsetText(offset)) (\(AppFormat.time(due))): \(title)"
        }
    }

    private static func offsetText(_ minutes: Int) -> String {
        switch minutes {
        case 60: return "ساعة"
        case 15: return "15 دقيقة"
        case 30: return "30 دقيقة"
        default: return "\(minutes) دقيقة"
        }
    }
}

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    static let categoryID = "TASK_REMINDER"
    static let doneAction = "MARK_DONE"
    static let snoozeAction = "SNOOZE_10"
    static let openAction = "OPEN_TASK"
    static let dailyBriefID = "daily.brief"

    private let center = UNUserNotificationCenter.current()
    private var syncTask: Task<Void, Never>?

    private override init() { super.init() }

    /// Must run before launch finishes so actions tapped while the app was closed are delivered.
    func configure() {
        center.delegate = self
        let done = UNNotificationAction(identifier: Self.doneAction, title: "تم التنفيذ ✓", options: [])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "تأجيل 10 دقائق", options: [])
        let open = UNNotificationAction(identifier: Self.openAction, title: "عرض المهمة", options: [.foreground])
        let category = UNNotificationCategory(identifier: Self.categoryID, actions: [done, snooze, open],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    // MARK: Authorization

    func requestAuthorizationIfNeeded() async -> Bool {
        let status = await currentAuthorizationStatus()
        if status == .notDetermined { return await requestPermission() }
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func pendingTaskReminderCount() async -> Int {
        await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("task.") || $0.identifier.hasPrefix("snooze.") }.count
    }

    // MARK: Task reminders

    static var remindersEnabled: Bool { UserDefaults.standard.bool(forKey: SettingsKey.remindersEnabled) }

    /// Debounced: the latest call wins.
    func requestSync(tasks: [TaskRecord]) {
        let planned = Self.remindersEnabled ? ReminderPlanner.plan(tasks: tasks, now: .now, calendar: AppCalendar.calendar) : []
        let openIDs = Set(tasks.filter { !$0.isCompleted }.map { $0.id.uuidString })
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            await self?.apply(planned: planned, openTaskIDs: openIDs)
        }
    }

    func syncNow(tasks: [TaskRecord]) async {
        let planned = Self.remindersEnabled ? ReminderPlanner.plan(tasks: tasks, now: .now, calendar: AppCalendar.calendar) : []
        await apply(planned: planned, openTaskIDs: Set(tasks.filter { !$0.isCompleted }.map { $0.id.uuidString }))
    }

    private func apply(planned: [PlannedReminder], openTaskIDs: Set<String>) async {
        let desired = Set(planned.map(\.identifier))
        let enabled = Self.remindersEnabled
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        if Task.isCancelled { return }
        let stale = pending.filter { id in
            if id.hasPrefix("task.") { return !desired.contains(id) }
            if id.hasPrefix("snooze.") { return !enabled || !openTaskIDs.contains(Self.taskID(fromIdentifier: id) ?? "") }
            return false
        }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        // Clear already-delivered banners of tasks that were deleted or completed.
        let delivered = await center.deliveredNotifications().map(\.request.identifier)
        let deliveredStale = delivered.filter { id in
            guard let taskID = Self.taskID(fromIdentifier: id) else { return false }
            return !openTaskIDs.contains(taskID)
        }
        center.removeDeliveredNotifications(withIdentifiers: deliveredStale)

        for item in planned {
            if Task.isCancelled { return }
            let content = UNMutableNotificationContent()
            content.title = "EGO FOCUS"
            content.body = item.body
            content.sound = .default
            content.categoryIdentifier = Self.categoryID
            content.threadIdentifier = item.taskID.uuidString
            content.userInfo = ["taskID": item.taskID.uuidString, "title": item.title]
            let components = AppCalendar.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            // Same identifier replaces the existing request: no duplicates.
            try? await center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger))
        }
    }

    /// "task.<uuid>.<offset>" or "snooze.<uuid>.<stamp>" → "<uuid>"
    static func taskID(fromIdentifier identifier: String) -> String? {
        let parts = identifier.split(separator: ".")
        guard parts.count >= 2, parts[0] == "task" || parts[0] == "snooze" else { return nil }
        return String(parts[1])
    }

    // MARK: Morning brief

    func scheduleDailyBrief() {
        let defaults = UserDefaults.standard
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyBriefID])
        guard defaults.bool(forKey: SettingsKey.dailyBriefEnabled) else { return }
        var components = DateComponents()
        components.hour = defaults.integer(forKey: SettingsKey.dailyBriefHour)
        components.minute = defaults.integer(forKey: SettingsKey.dailyBriefMinute)
        let content = UNMutableNotificationContent()
        content.title = "صباحك منظّم مع EGO FOCUS"
        content.body = "ركّز على ما يهمك. افتح التطبيق لمراجعة مهام اليوم وأولوياتك."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: Self.dailyBriefID, content: content, trigger: trigger))
    }

    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "EGO FOCUS"
        content.body = "هذا تنبيه تجريبي — التنبيهات تعمل."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        center.add(UNNotificationRequest(identifier: "test.\(UUID().uuidString)", content: content, trigger: trigger))
    }

    // MARK: Actions

    func snooze(taskID: UUID, title: String, minutes: Int = 10) async {
        let content = UNMutableNotificationContent()
        content.title = "EGO FOCUS — تذكير مؤجل"
        content.body = title.isEmpty ? "تذكير بمهمتك" : title
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.threadIdentifier = taskID.uuidString
        content.userInfo = ["taskID": taskID.uuidString, "title": title]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        let identifier = "snooze.\(taskID.uuidString).\(Int(Date().timeIntervalSince1970))"
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    func handle(action: String, taskIDString: String?, title: String, context: ModelContext? = nil) async {
        guard let taskIDString, let id = UUID(uuidString: taskIDString) else { return }
        let context = context ?? Persistence.shared.mainContext
        switch action {
        case Self.snoozeAction:
            await snooze(taskID: id, title: title)
        case Self.doneAction:
            guard let task = TaskOperations.fetchTask(id: id, in: context) else { return }
            TaskOperations.complete(task, in: context, now: .now)
            try? context.save()
            NotificationCenter.default.post(name: .egoTasksDidChange, object: nil)
            await syncNow(tasks: TaskOperations.fetchAllTasks(in: context))
        case Self.openAction, UNNotificationDefaultActionIdentifier:
            NotificationCenter.default.post(name: .egoOpenTask, object: id)
        default:
            break
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let taskID = info["taskID"] as? String
        let title = info["title"] as? String ?? ""
        let action = response.actionIdentifier
        Task { @MainActor in
            await NotificationService.shared.handle(action: action, taskIDString: taskID, title: title)
            completionHandler()
        }
    }
}
