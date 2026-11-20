import Foundation

/// Arabic locale with Latin digits and the Gregorian calendar, used consistently for
/// formatting so the UI is Arabic even when the device language is English, and stays
/// Gregorian even when the device calendar is set to Hijri.
enum AppLocale {
    static let arabic = Locale(identifier: "ar@numbers=latn")
}

enum AppCalendar {
    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = AppLocale.arabic
        cal.timeZone = TimeZone.current
        cal.firstWeekday = 1 // الأحد
        return cal
    }
}

enum AppFormat {
    private static var base: Date.FormatStyle {
        Date.FormatStyle(locale: AppLocale.arabic, calendar: AppCalendar.calendar, timeZone: TimeZone.current)
    }

    static func time(_ date: Date) -> String { date.formatted(base.hour().minute()) }
    static func dayMonth(_ date: Date) -> String { date.formatted(base.weekday(.wide).day().month(.wide)) }
    static func shortDay(_ date: Date) -> String { date.formatted(base.day().month(.abbreviated)) }
    static func monthYear(_ date: Date) -> String { date.formatted(base.month(.wide).year()) }
    static func dayNumber(_ date: Date) -> String { date.formatted(base.day()) }
    static func weekdayShort(_ date: Date) -> String { date.formatted(base.weekday(.abbreviated)) }
    static func full(_ date: Date) -> String {
        date.formatted(base.weekday(.wide).day().month(.wide).year().hour().minute())
    }
    static func dateTimeShort(_ date: Date) -> String {
        date.formatted(base.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }
    static func fullDate(_ date: Date) -> String { date.formatted(base.weekday(.wide).day().month(.wide).year()) }
    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))٪" }

    static func reminderLabel(_ offset: Int) -> String {
        switch offset {
        case 0: return "في وقت المهمة"
        case 15: return "قبلها بـ 15 دقيقة"
        case 30: return "قبلها بـ 30 دقيقة"
        case 60: return "قبلها بساعة"
        case 1440: return "قبلها بيوم"
        default: return "قبلها بـ \(offset) دقيقة"
        }
    }
}

enum ReminderOption {
    /// Supported reminder offsets in minutes before the due time.
    static let all: [Int] = [0, 15, 30, 60, 1440]
}

enum SettingsKey {
    static let appearance = "egofocus_appearance"
    static let remindersEnabled = "egofocus_reminders_enabled"
    static let defaultReminder = "egofocus_default_reminder"          // -1 = بدون
    static let dailyBriefEnabled = "egofocus_daily_brief_enabled"
    static let dailyBriefHour = "egofocus_daily_brief_hour"
    static let dailyBriefMinute = "egofocus_daily_brief_minute"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            appearance: "system",
            remindersEnabled: true,
            defaultReminder: 0,
            dailyBriefEnabled: false,
            dailyBriefHour: 8,
            dailyBriefMinute: 0
        ])
    }

    static var defaultReminderOffsets: [Int] {
        let value = UserDefaults.standard.integer(forKey: defaultReminder)
        return value < 0 ? [] : [value]
    }
}

/// Launch arguments used by UI tests and by the screenshot step of the CI build.
enum LaunchOptions {
    private static var args: [String] { ProcessInfo.processInfo.arguments }
    static var isUITesting: Bool { args.contains("-uiTesting") }
    static var resetStore: Bool { args.contains("-resetStore") }
    static var seedDemoData: Bool { args.contains("-demoData") }
    static var openAssistant: Bool { args.contains("-openAssistant") }
    static var openEditor: Bool { args.contains("-openEditor") }
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil && !isUITesting
    }
    static var initialTab: String? {
        guard let index = args.firstIndex(of: "-tab"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}

extension Notification.Name {
    /// Posted when tasks change outside the store (e.g. from a notification action).
    static let egoTasksDidChange = Notification.Name("EGOFocus.tasksDidChange")
    /// Posted with a task UUID as `object` when the user opens a task from a notification.
    static let egoOpenTask = Notification.Name("EGOFocus.openTask")
}
