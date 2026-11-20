import Foundation
import SwiftData

/// Sample data, inserted only when the app is launched with `-demoData`
/// (used for the CI screenshots). Never used in normal launches.
@MainActor
enum DemoData {
    static func seed(into context: ModelContext, now: Date, calendar: Calendar) {
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let hourNow = calendar.component(.hour, from: now)
        let laterToday = min(hourNow + 2, 23)

        let items: [TaskRecord] = [
            TaskRecord(title: "مراجعة الفواتير الشهرية", details: "مطابقة فواتير الموردين مع كشف الحساب",
                       dueDate: at(0, laterToday), priority: .urgent, category: .finance, reminderOffsets: [0, 30]),
            TaskRecord(title: "اجتماع فريق المبيعات", details: "مناقشة أهداف الربع القادم",
                       dueDate: at(0, min(laterToday + 1, 23), 30), priority: .high, category: .work, reminderOffsets: [15]),
            TaskRecord(title: "تمرين المشي", dueDate: at(0, min(laterToday + 2, 23)), priority: .normal,
                       category: .health, recurrence: .daily, reminderOffsets: [0]),
            TaskRecord(title: "إرسال عرض السعر للعميل", dueDate: at(-1, 11), priority: .high, category: .work),
            TaskRecord(title: "شراء مستلزمات المكتب", dueDate: at(1, 10), priority: .normal, category: .work),
            TaskRecord(title: "قراءة فصل من كتاب الإدارة", dueDate: at(2, 21), priority: .low, category: .learning),
            TaskRecord(title: "دفع الإيجار", notes: "التحويل البنكي قبل الظهر", dueDate: at(5, 9),
                       priority: .urgent, category: .finance, recurrence: .monthly,
                       recurrenceAnchorDay: calendar.component(.day, from: at(5, 9)), reminderOffsets: [1440]),
            TaskRecord(title: "موعد طبيب الأسنان", dueDate: at(8, 17), priority: .normal, category: .health, reminderOffsets: [60])
        ]
        items.forEach { context.insert($0) }

        let finished: [(String, TaskCategory, Int)] = [
            ("تحديث خطة الأسبوع", .work, 0), ("الرد على بريد المورد", .work, -1),
            ("تسديد فاتورة الكهرباء", .finance, -2), ("مراجعة الدرس الثالث", .learning, -3),
            ("ترتيب المكتب", .personal, -4)
        ]
        for (title, category, offset) in finished {
            let date = at(offset, 9)
            let task = TaskRecord(title: title, dueDate: date, priority: .normal, category: category, reminderOffsets: [])
            context.insert(task)
            TaskOperations.complete(task, in: context, now: date.addingTimeInterval(1800), calendar: calendar)
        }
        try? context.save()
    }
}
