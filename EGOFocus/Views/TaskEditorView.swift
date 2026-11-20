import SwiftUI

struct TaskEditorView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.remindersEnabled) private var remindersEnabled = true

    private let existingTask: TaskRecord?
    @State private var draft: TaskDraft
    @State private var remindersOn: Bool
    @State private var confirmDelete = false

    init(existingTask: TaskRecord? = nil, initialDate: Date? = nil) {
        self.existingTask = existingTask
        let draft: TaskDraft
        if let existingTask {
            draft = TaskDraft(task: existingTask)
        } else {
            var start = TaskDraft.suggestedDueDate()
            if let initialDate {
                let calendar = AppCalendar.calendar
                let time = calendar.dateComponents([.hour, .minute], from: start)
                start = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: initialDate) ?? initialDate
            }
            draft = TaskDraft(dueDate: start)
        }
        _draft = State(initialValue: draft)
        _remindersOn = State(initialValue: !draft.reminderOffsets.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("المهمة") {
                    TextField("عنوان المهمة", text: $draft.title)
                        .font(.body.weight(.semibold))
                        .accessibilityIdentifier("editor.title")
                    TextField("الوصف", text: $draft.details, axis: .vertical)
                        .lineLimit(1...4)
                        .accessibilityIdentifier("editor.details")
                }

                Section("الموعد") {
                    DatePicker("التاريخ والوقت", selection: $draft.dueDate, displayedComponents: [.date, .hourAndMinute])
                    quickDates
                }

                Section("التصنيف والأولوية") {
                    Picker("التصنيف", selection: $draft.category) {
                        ForEach(TaskCategory.allCases) { category in
                            Label(category.rawValue, systemImage: category.symbol).tag(category)
                        }
                    }
                    Picker("الأولوية", selection: $draft.priority) {
                        ForEach(TaskPriority.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Picker("التكرار", selection: $draft.recurrence) {
                        ForEach(TaskRecurrence.allCases) { Text($0.rawValue).tag($0) }
                    }
                } header: {
                    Text("التكرار")
                } footer: {
                    if let note = recurrenceNote { Text(note) }
                }

                Section {
                    Toggle("تفعيل التذكير", isOn: $remindersOn.animation())
                        .accessibilityIdentifier("editor.remindersToggle")
                    if remindersOn {
                        ForEach(ReminderOption.all, id: \.self) { offset in
                            Toggle(AppFormat.reminderLabel(offset), isOn: offsetBinding(offset))
                        }
                    }
                } header: {
                    Text("التذكير")
                } footer: {
                    if !remindersEnabled {
                        Text("التذكيرات متوقفة من الإعدادات؛ لن تصلك تنبيهات حتى تفعّلها.")
                    } else if remindersOn && draft.reminderOffsets.isEmpty {
                        Text("اختر وقتاً واحداً على الأقل للتذكير.")
                    }
                }

                Section("ملاحظات") {
                    TextField("أضف ملاحظات", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("editor.notes")
                }

                if let task = existingTask {
                    Section {
                        Button {
                            store.toggleCompletion(task)
                            dismiss()
                        } label: {
                            Label(task.isCompleted ? "إعادة فتح المهمة" : (task.recurrence == .none ? "تم التنفيذ" : "تم التنفيذ (الانتقال للموعد التالي)"),
                                  systemImage: task.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle")
                        }
                        .accessibilityIdentifier("editor.toggleComplete")
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("حذف المهمة", systemImage: "trash")
                        }
                        .accessibilityIdentifier("editor.delete")
                    }
                }
            }
            .navigationTitle(existingTask == nil ? "مهمة جديدة" : "تعديل المهمة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ", action: save)
                        .fontWeight(.bold)
                        .disabled(!draft.isValid)
                        .accessibilityIdentifier("editor.save")
                }
            }
            .confirmationDialog("حذف هذه المهمة نهائياً؟", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("حذف نهائياً", role: .destructive) {
                    if let task = existingTask {
                        dismiss()
                        store.delete(task)
                    }
                }
                Button("إلغاء", role: .cancel) {}
            } message: {
                Text("سيتم حذف المهمة وتذكيراتها وسجل إنجازها من هذا الجهاز.")
            }
        }
    }

    private var quickDates: some View {
        let calendar = AppCalendar.calendar
        let options: [(String, Int)] = [("اليوم", 0), ("غداً", 1), ("بعد أسبوع", 7)]
        return HStack(spacing: 8) {
            ForEach(options, id: \.1) { option in
                Button(option.0) {
                    let time = calendar.dateComponents([.hour, .minute], from: draft.dueDate)
                    let day = calendar.date(byAdding: .day, value: option.1, to: calendar.startOfDay(for: store.now)) ?? store.now
                    draft.dueDate = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day) ?? day
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .font(.footnote)
            }
        }
    }

    private var recurrenceNote: String? {
        let calendar = AppCalendar.calendar
        switch draft.recurrence {
        case .none: return nil
        case .daily: return "عند إنجازها تنتقل المهمة إلى اليوم التالي في نفس الوقت."
        case .weekly: return "تتكرر كل \(AppFormat.weekdayShort(draft.dueDate)) في نفس الوقت."
        case .monthly:
            let day = calendar.component(.day, from: draft.dueDate)
            if day > 28 {
                return "تتكرر يوم \(day) من كل شهر؛ وفي الأشهر الأقصر تكون في آخر يوم من الشهر."
            }
            return "تتكرر يوم \(day) من كل شهر."
        }
    }

    private func offsetBinding(_ offset: Int) -> Binding<Bool> {
        Binding(
            get: { draft.reminderOffsets.contains(offset) },
            set: { enabled in
                var set = Set(draft.reminderOffsets)
                if enabled { set.insert(offset) } else { set.remove(offset) }
                draft.reminderOffsets = set.sorted()
            })
    }

    private func save() {
        var final = draft
        if !remindersOn { final.reminderOffsets = [] }
        if let existingTask {
            store.update(existingTask, with: final)
        } else {
            store.add(final)
        }
        dismiss()
    }
}
