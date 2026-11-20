import Foundation
import SwiftData

enum TaskPriority: String, CaseIterable, Identifiable, Codable {
    case low = "منخفضة"
    case normal = "عادية"
    case high = "مرتفعة"
    case urgent = "عاجلة"
    var id: String { rawValue }

    /// Higher = more important. Used for sorting tasks that share a due time.
    var rank: Int {
        switch self {
        case .low: return 0
        case .normal: return 1
        case .high: return 2
        case .urgent: return 3
        }
    }

    var symbol: String {
        switch self {
        case .low: return "arrow.down"
        case .normal: return "minus"
        case .high: return "arrow.up"
        case .urgent: return "exclamationmark.2"
        }
    }
}

enum TaskCategory: String, CaseIterable, Identifiable, Codable {
    case work = "العمل"
    case finance = "المالية"
    case personal = "شخصي"
    case learning = "التعلم"
    case health = "الصحة"
    case other = "أخرى"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .work: return "briefcase"
        case .finance: return "banknote"
        case .personal: return "person"
        case .learning: return "book"
        case .health: return "heart"
        case .other: return "square.grid.2x2"
        }
    }
}

enum TaskRecurrence: String, CaseIterable, Identifiable, Codable {
    case none = "بدون تكرار"
    case daily = "يومياً"
    case weekly = "أسبوعياً"
    case monthly = "شهرياً"
    var id: String { rawValue }
}

@Model
final class TaskRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    /// وصف المهمة (منفصل عن الملاحظات).
    var details: String = ""
    var notes: String
    /// For a recurring task this is the date of the *next open occurrence*.
    var dueDate: Date
    var priorityRaw: String
    var categoryRaw: String
    var isCompleted: Bool
    var completedAt: Date?
    var recurrenceRaw: String
    /// Original day-of-month for monthly recurrence (so the 31st returns after short months).
    var recurrenceAnchorDay: Int = 0
    /// Comma separated minutes-before-due. Empty = no reminder.
    var reminderOffsetsRaw: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \CompletionEvent.task)
    var completions: [CompletionEvent] = []

    init(id: UUID = UUID(), title: String, details: String = "", notes: String = "", dueDate: Date,
         priority: TaskPriority = .normal, category: TaskCategory = .personal,
         isCompleted: Bool = false, recurrence: TaskRecurrence = .none,
         recurrenceAnchorDay: Int = 0, reminderOffsets: [Int] = [0], createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.details = details
        self.notes = notes
        self.dueDate = dueDate
        self.priorityRaw = priority.rawValue
        self.categoryRaw = category.rawValue
        self.isCompleted = isCompleted
        self.completedAt = nil
        self.recurrenceRaw = recurrence.rawValue
        self.recurrenceAnchorDay = recurrenceAnchorDay
        self.reminderOffsetsRaw = TaskRecord.encode(reminderOffsets)
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    var category: TaskCategory {
        get { TaskCategory(rawValue: categoryRaw) ?? .personal }
        set { categoryRaw = newValue.rawValue }
    }

    var recurrence: TaskRecurrence {
        get { TaskRecurrence(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }

    var reminderOffsets: [Int] {
        get { reminderOffsetsRaw.split(separator: ",").compactMap { Int($0) } }
        set { reminderOffsetsRaw = TaskRecord.encode(newValue) }
    }

    func isOverdue(now: Date) -> Bool { !isCompleted && dueDate < now }

    static func encode(_ offsets: [Int]) -> String {
        Array(Set(offsets)).filter { $0 >= 0 }.sorted().map(String.init).joined(separator: ",")
    }
}

/// One record per completion. Recurring tasks keep a history of completions while their
/// `dueDate` moves forward; reports count these events. Deleted with the task (cascade).
@Model
final class CompletionEvent {
    var completedAt: Date
    var scheduledFor: Date
    var task: TaskRecord?

    init(completedAt: Date, scheduledFor: Date) {
        self.completedAt = completedAt
        self.scheduledFor = scheduledFor
    }
}

/// Pure recurrence rules (no persistence) so they can be unit tested.
enum RecurrenceEngine {
    /// Next occurrence strictly after `date`.
    /// Monthly rule: keep the anchor day; if the month is shorter, use its last day,
    /// then return to the anchor day in longer months (31 Jan → 28/29 Feb → 31 Mar).
    static func next(after date: Date, rule: TaskRecurrence, anchorDay: Int, calendar: Calendar) -> Date {
        switch rule {
        case .none:
            return date
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date.addingTimeInterval(7 * 86_400)
        case .monthly:
            let day = anchorDay > 0 ? anchorDay : calendar.component(.day, from: date)
            let monthStart = startOfMonth(date, calendar)
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return date }
            return dateIn(month: nextMonth, day: day, timeFrom: date, calendar: calendar)
        }
    }

    /// Advances at least once, and keeps advancing until the occurrence is after `limit`.
    static func nextOccurrence(from date: Date, after limit: Date, rule: TaskRecurrence,
                               anchorDay: Int, calendar: Calendar) -> Date {
        guard rule != .none else { return date }
        var result = next(after: date, rule: rule, anchorDay: anchorDay, calendar: calendar)
        var guardCounter = 0
        while result <= limit && guardCounter < 5000 {
            result = next(after: result, rule: rule, anchorDay: anchorDay, calendar: calendar)
            guardCounter += 1
        }
        return result
    }

    /// Whether a series starting at `start` has an occurrence on `day` (only on/after start).
    static func occurs(on day: Date, start: Date, rule: TaskRecurrence, anchorDay: Int, calendar: Calendar) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        let seriesStart = calendar.startOfDay(for: start)
        if rule == .none { return dayStart == seriesStart }
        if dayStart < seriesStart { return false }
        switch rule {
        case .none:
            return false
        case .daily:
            return true
        case .weekly:
            return calendar.component(.weekday, from: day) == calendar.component(.weekday, from: start)
        case .monthly:
            let anchor = anchorDay > 0 ? anchorDay : calendar.component(.day, from: start)
            let count = calendar.range(of: .day, in: .month, for: day)?.count ?? 28
            return calendar.component(.day, from: day) == min(anchor, count)
        }
    }

    /// The occurrence of the series that falls on `day` (with the series time of day).
    static func occurrence(on day: Date, timeFrom: Date, calendar: Calendar) -> Date {
        let time = calendar.dateComponents([.hour, .minute], from: timeFrom)
        return calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day) ?? day
    }

    static func startOfMonth(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    static func dateIn(month: Date, day: Int, timeFrom: Date, calendar: Calendar) -> Date {
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
        var components = calendar.dateComponents([.year, .month], from: month)
        let time = calendar.dateComponents([.hour, .minute], from: timeFrom)
        components.day = min(max(day, 1), count)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        return calendar.date(from: components) ?? month
    }
}
