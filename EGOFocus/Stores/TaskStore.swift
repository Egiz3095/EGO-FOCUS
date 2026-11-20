import Foundation
import SwiftUI
import SwiftData

/// Editable copy of a task used by the editor and the assistant preview.
struct TaskDraft: Equatable {
    var title: String = ""
    var details: String = ""
    var notes: String = ""
    var dueDate: Date
    var priority: TaskPriority = .normal
    var category: TaskCategory = .personal
    var recurrence: TaskRecurrence = .none
    var reminderOffsets: [Int] = [0]

    init(dueDate: Date, reminderOffsets: [Int] = SettingsKey.defaultReminderOffsets) {
        self.dueDate = dueDate
        self.reminderOffsets = reminderOffsets
    }

    init(task: TaskRecord) {
        title = task.title
        details = task.details
        notes = task.notes
        dueDate = task.dueDate
        priority = task.priority
        category = task.category
        recurrence = task.recurrence
        reminderOffsets = task.reminderOffsets
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isValid: Bool { !trimmedTitle.isEmpty }

    /// Next full hour (today), or 9:00 tomorrow when it is late.
    static func suggestedDueDate(now: Date = .now, calendar: Calendar = AppCalendar.calendar) -> Date {
        let hour = calendar.component(.hour, from: now)
        if hour >= 22 {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? now
        }
        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
        return calendar.date(byAdding: .hour, value: 1, to: start) ?? now
    }
}

/// Persistence-level operations shared by the store and notification actions.
@MainActor
enum TaskOperations {
    static func complete(_ task: TaskRecord, in context: ModelContext, now: Date,
                         calendar: Calendar = AppCalendar.calendar) {
        guard !task.isCompleted else { return }
        let event = CompletionEvent(completedAt: now, scheduledFor: task.dueDate)
        context.insert(event)
        event.task = task
        if task.recurrence == .none {
            task.isCompleted = true
            task.completedAt = now
        } else {
            // Move the series to its next occurrence after now — never creates a duplicate task.
            task.dueDate = RecurrenceEngine.nextOccurrence(from: task.dueDate, after: now,
                                                           rule: task.recurrence,
                                                           anchorDay: task.recurrenceAnchorDay,
                                                           calendar: calendar)
            task.isCompleted = false
            task.completedAt = nil
        }
        task.updatedAt = now
    }

    static func reopen(_ task: TaskRecord, in context: ModelContext, now: Date) {
        guard task.isCompleted else { return }
        task.isCompleted = false
        task.completedAt = nil
        task.updatedAt = now
        if let last = task.completions.max(by: { $0.completedAt < $1.completedAt }) {
            context.delete(last)
        }
    }

    static func fetchTask(id: UUID, in context: ModelContext) -> TaskRecord? {
        let taskID = id
        var descriptor = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == taskID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func fetchAllTasks(in context: ModelContext) -> [TaskRecord] {
        (try? context.fetch(FetchDescriptor<TaskRecord>(sortBy: [SortDescriptor(\.dueDate)]))) ?? []
    }
}

enum ReportPeriod: String, CaseIterable, Identifiable {
    case day = "اليوم"
    case week = "الأسبوع"
    case month = "الشهر"
    var id: String { rawValue }
}

struct PeriodStats: Equatable {
    var interval: DateInterval
    var completed: Int
    var pending: Int
    var overdue: Int
    var total: Int { completed + pending + overdue }
    var completionRate: Double { total == 0 ? 0 : Double(completed) / Double(total) }
}

struct DayCount: Identifiable, Equatable {
    var day: Date
    var count: Int
    var id: Date { day }
}

/// An entry on the calendar: a real task, or a projected future occurrence of a recurring one.
struct CalendarItem: Identifiable {
    let task: TaskRecord
    let date: Date
    let isProjection: Bool
    var id: String { "\(task.id.uuidString)-\(date.timeIntervalSince1970)" }
}

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskRecord] = []
    @Published private(set) var events: [CompletionEvent] = []
    @Published var lastError: String?

    /// Retained so the context stays valid for the store's lifetime.
    let container: ModelContainer
    let context: ModelContext
    let syncsNotifications: Bool
    var clock: () -> Date = { Date() }
    var calendar: Calendar { AppCalendar.calendar }
    private var observer: NSObjectProtocol?

    init(container: ModelContainer, syncsNotifications: Bool = true) {
        self.container = container
        self.context = container.mainContext
        self.syncsNotifications = syncsNotifications
        refresh()
        observer = NotificationCenter.default.addObserver(forName: .egoTasksDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var now: Date { clock() }

    // MARK: Loading

    func refresh() {
        do {
            tasks = try context.fetch(FetchDescriptor<TaskRecord>(sortBy: [SortDescriptor(\.dueDate)]))
            events = try context.fetch(FetchDescriptor<CompletionEvent>(sortBy: [SortDescriptor(\.completedAt, order: .reverse)]))
        } catch {
            lastError = "تعذر قراءة المهام: \(error.localizedDescription)"
        }
    }

    func onLaunch() async {
        if LaunchOptions.seedDemoData && tasks.isEmpty {
            DemoData.seed(into: context, now: now, calendar: calendar)
            persist()
        }
        guard syncsNotifications, !LaunchOptions.isRunningUnitTests else { return }
        NotificationService.shared.scheduleDailyBrief()
        if !LaunchOptions.isUITesting {
            _ = await NotificationService.shared.requestAuthorizationIfNeeded()
        }
        syncNotifications()
    }

    func syncNotifications() {
        guard syncsNotifications, !LaunchOptions.isRunningUnitTests else { return }
        NotificationService.shared.requestSync(tasks: tasks)
    }

    // MARK: Derived lists

    private static func order(_ a: TaskRecord, _ b: TaskRecord) -> Bool {
        if a.dueDate != b.dueDate { return a.dueDate < b.dueDate }
        return a.priority.rank > b.priority.rank
    }

    var pending: [TaskRecord] { tasks.filter { !$0.isCompleted }.sorted(by: Self.order) }
    var overdue: [TaskRecord] { let n = now; return pending.filter { $0.dueDate < n } }
    var todayOpen: [TaskRecord] {
        let n = now
        return pending.filter { $0.dueDate >= n && calendar.isDate($0.dueDate, inSameDayAs: n) }
    }
    var upcoming: [TaskRecord] {
        let end = endOfDay(now)
        return pending.filter { $0.dueDate >= end }
    }
    var completedTasks: [TaskRecord] {
        tasks.filter(\.isCompleted).sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
    }

    func task(id: UUID) -> TaskRecord? { tasks.first { $0.id == id } }

    // MARK: Calendar

    func items(on day: Date) -> [CalendarItem] {
        var result: [CalendarItem] = []
        for task in tasks {
            if calendar.isDate(task.dueDate, inSameDayAs: day) {
                result.append(CalendarItem(task: task, date: task.dueDate, isProjection: false))
            } else if !task.isCompleted, task.recurrence != .none,
                      RecurrenceEngine.occurs(on: day, start: task.dueDate, rule: task.recurrence,
                                              anchorDay: task.recurrenceAnchorDay, calendar: calendar) {
                let date = RecurrenceEngine.occurrence(on: day, timeFrom: task.dueDate, calendar: calendar)
                result.append(CalendarItem(task: task, date: date, isProjection: true))
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    /// Highest priority among open items that day (`.low` when only completed items, nil when empty).
    func indicatorPriority(on day: Date) -> TaskPriority? {
        let list = items(on: day)
        guard !list.isEmpty else { return nil }
        return list.filter { !$0.task.isCompleted }.map(\.task.priority).max { $0.rank < $1.rank } ?? .low
    }

    // MARK: Reports

    func interval(for period: ReportPeriod, containing date: Date? = nil) -> DateInterval {
        let reference = date ?? now
        let component: Calendar.Component
        switch period {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        }
        return calendar.dateInterval(of: component, for: reference) ?? DateInterval(start: reference, duration: 86_400)
    }

    func stats(for period: ReportPeriod) -> PeriodStats {
        let range = interval(for: period)
        let n = now
        let completed = events.filter { $0.completedAt >= range.start && $0.completedAt < range.end }.count
        let open = pending.filter { $0.dueDate >= range.start && $0.dueDate < range.end }
        let overdue = open.filter { $0.dueDate < n }.count
        return PeriodStats(interval: range, completed: completed, pending: open.count - overdue, overdue: overdue)
    }

    func dailyCompletions(for period: ReportPeriod) -> [DayCount] {
        let range = interval(for: period)
        var days: [DayCount] = []
        var cursor = range.start
        while cursor < range.end {
            let next = calendar.date(byAdding: .day, value: 1, to: cursor) ?? range.end
            let count = events.filter { $0.completedAt >= cursor && $0.completedAt < next }.count
            days.append(DayCount(day: cursor, count: count))
            cursor = next
        }
        return days
    }

    func completionsByCategory(for period: ReportPeriod) -> [(TaskCategory, Int)] {
        let range = interval(for: period)
        var counts: [TaskCategory: Int] = [:]
        for event in events where event.completedAt >= range.start && event.completedAt < range.end {
            let category = event.task?.category ?? .other
            counts[category, default: 0] += 1
        }
        return TaskCategory.allCases.compactMap { c in counts[c].map { (c, $0) } }.sorted { $0.1 > $1.1 }
    }

    /// All-time: completions recorded vs. completions + still-open tasks.
    var overallCompletionRate: Double {
        let total = events.count + pending.count
        return total == 0 ? 0 : Double(events.count) / Double(total)
    }

    // MARK: Mutations

    @discardableResult
    func add(_ draft: TaskDraft) -> TaskRecord? {
        guard draft.isValid else { return nil }
        let task = TaskRecord(title: draft.trimmedTitle,
                              details: draft.details.trimmingCharacters(in: .whitespacesAndNewlines),
                              notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                              dueDate: Self.clean(draft.dueDate, calendar),
                              priority: draft.priority, category: draft.category,
                              recurrence: draft.recurrence,
                              recurrenceAnchorDay: draft.recurrence == .monthly ? calendar.component(.day, from: draft.dueDate) : 0,
                              reminderOffsets: draft.reminderOffsets, createdAt: now)
        context.insert(task)
        persist()
        return task
    }

    func update(_ task: TaskRecord, with draft: TaskDraft) {
        guard draft.isValid else { return }
        let newDue = Self.clean(draft.dueDate, calendar)
        let scheduleChanged = newDue != task.dueDate || draft.recurrence != task.recurrence
        task.title = draft.trimmedTitle
        task.details = draft.details.trimmingCharacters(in: .whitespacesAndNewlines)
        task.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        task.dueDate = newDue
        task.priority = draft.priority
        task.category = draft.category
        task.recurrence = draft.recurrence
        if draft.recurrence != .monthly {
            task.recurrenceAnchorDay = 0
        } else if scheduleChanged || task.recurrenceAnchorDay == 0 {
            task.recurrenceAnchorDay = calendar.component(.day, from: newDue)
        }
        task.reminderOffsets = draft.reminderOffsets
        task.updatedAt = now
        persist()
    }

    func toggleCompletion(_ task: TaskRecord) {
        if task.isCompleted {
            TaskOperations.reopen(task, in: context, now: now)
        } else {
            TaskOperations.complete(task, in: context, now: now, calendar: calendar)
        }
        persist()
    }

    func delete(_ task: TaskRecord) {
        context.delete(task) // completion events are removed by the cascade rule
        persist()
    }

    /// Quick add from the home screen: title only, due at the next full hour.
    @discardableResult
    func quickAdd(title: String) -> TaskRecord? {
        var draft = TaskDraft(dueDate: TaskDraft.suggestedDueDate(now: now, calendar: calendar))
        draft.title = title
        return add(draft)
    }

    private func persist() {
        do {
            try context.save()
        } catch {
            lastError = "تعذر حفظ التغييرات: \(error.localizedDescription)"
        }
        refresh()
        syncNotifications()
    }

    private func endOfDay(_ date: Date) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date
    }

    /// Drop seconds so reminders fire on the minute.
    private static func clean(_ date: Date, _ calendar: Calendar) -> Date {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: c) ?? date
    }
}
