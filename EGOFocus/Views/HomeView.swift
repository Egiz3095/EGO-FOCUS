import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: TaskStore
    let onAdd: () -> Void
    let onAssistant: () -> Void

    @State private var editingTask: TaskRecord?
    @State private var quickTitle = ""
    @State private var showAllCompleted = false
    @FocusState private var quickFieldFocused: Bool

    private var greeting: String {
        let hour = AppCalendar.calendar.component(.hour, from: store.now)
        switch hour {
        case 4..<12: return "صباح الخير"
        case 12..<17: return "نهارك سعيد"
        default: return "مساء الخير"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    quickAdd
                    summaryCard
                    overdueSection
                    todaySection
                    upcomingSection
                    completedSection
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 90)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Brand.canvas.ignoresSafeArea())
            .overlay(alignment: .bottomTrailing) { AddTaskButton(action: onAdd) }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editingTask) { task in
                TaskEditorView(existingTask: task).environmentObject(store)
            }
            .navigationDestination(for: String.self) { value in
                if value == "all" { AllTasksView() }
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppFormat.dayMonth(store.now))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(greeting)
                    .font(.largeTitle.weight(.bold))
                Text("ركّز على ما يهمك.")
                    .font(.subheadline)
                    .foregroundStyle(Brand.accent)
            }
            Spacer()
            NavigationLink(value: "all") {
                Image(systemName: "list.bullet")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(Brand.card, in: Circle())
            }
            .accessibilityLabel("كل المهام")
            .accessibilityIdentifier("home.allTasks")
        }
        .padding(.top, 12)
    }

    private var quickAdd: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(Brand.accent)
            TextField("أضف مهمة سريعة…", text: $quickTitle)
                .focused($quickFieldFocused)
                .submitLabel(.done)
                .onSubmit(submitQuickTask)
                .accessibilityIdentifier("home.quickAdd")
            if quickTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: onAssistant) {
                    Image(systemName: "mic.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Brand.onAccent)
                        .frame(width: 34, height: 34)
                        .background(Brand.accent, in: Circle())
                }
                .accessibilityLabel("المساعد الذكي والإملاء الصوتي")
                .accessibilityIdentifier("home.assistant")
            } else {
                Button("إضافة", action: submitQuickTask)
                    .font(.subheadline.weight(.bold))
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var summaryCard: some View {
        let today = store.stats(for: .day)
        return HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ملخص إنتاجيتك اليوم")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                Text("أنجزت \(today.completed) من \(today.total)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                HStack(spacing: 12) {
                    summaryPill("\(store.todayOpen.count)", "متبقية اليوم")
                    summaryPill("\(store.overdue.count)", "متأخرة")
                    summaryPill("\(store.upcoming.count)", "قادمة")
                }
            }
            Spacer(minLength: 0)
            ZStack {
                ProgressRing(progress: today.completionRate, lineWidth: 8, tint: Color(red: 0.43, green: 0.85, blue: 0.72))
                Text(AppFormat.percent(today.completionRate))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
            }
            .frame(width: 74, height: 74)
        }
        .padding(18)
        .background(Brand.heroGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.summary")
    }

    private func summaryPill(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(.white)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.75))
        }
    }

    @ViewBuilder private var overdueSection: some View {
        if !store.overdue.isEmpty {
            SectionHeader(title: "مهام متأخرة", count: store.overdue.count, tint: .red)
            ForEach(store.overdue) { task in
                TaskRow(task: task) { editingTask = task }
            }
        }
    }

    @ViewBuilder private var todaySection: some View {
        SectionHeader(title: "مهام اليوم", count: store.todayOpen.count)
        if store.todayOpen.isEmpty {
            EmptyStateCard(icon: "sun.max",
                           title: store.overdue.isEmpty ? "لا مهام متبقية لليوم" : "لا مهام أخرى لليوم",
                           message: "أضف مهمة جديدة أو استخدم المساعد الصوتي لتنظيم يومك.")
        } else {
            ForEach(store.todayOpen) { task in
                TaskRow(task: task, showsDay: false) { editingTask = task }
            }
        }
    }

    @ViewBuilder private var upcomingSection: some View {
        SectionHeader(title: "المهام القادمة", count: store.upcoming.count)
        if store.upcoming.isEmpty {
            EmptyStateCard(icon: "calendar.badge.clock", title: "لا مهام قادمة",
                           message: "جدولك القادم فارغ. خطّط لأسبوعك من التقويم.")
        } else {
            ForEach(store.upcoming.prefix(6)) { task in
                TaskRow(task: task) { editingTask = task }
            }
            if store.upcoming.count > 6 {
                NavigationLink(value: "all") {
                    Text("عرض كل المهام القادمة (\(store.upcoming.count))")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder private var completedSection: some View {
        let completed = store.completedTasks
        if !completed.isEmpty {
            SectionHeader(title: "المهام المكتملة", count: completed.count)
            ForEach(completed.prefix(showAllCompleted ? 30 : 3)) { task in
                TaskRow(task: task) { editingTask = task }
            }
            if completed.count > 3 {
                Button(showAllCompleted ? "عرض أقل" : "عرض المزيد") {
                    withAnimation { showAllCompleted.toggle() }
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func submitQuickTask() {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        store.quickAdd(title: title)
        quickTitle = ""
        quickFieldFocused = false
    }
}

/// Full task list with filter, search and swipe actions.
struct AllTasksView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var filter: Filter = .open
    @State private var search = ""
    @State private var editingTask: TaskRecord?

    enum Filter: String, CaseIterable, Identifiable {
        case open = "قيد التنفيذ"
        case completed = "المكتملة"
        case all = "الكل"
        var id: String { rawValue }
    }

    private var items: [TaskRecord] {
        let base: [TaskRecord]
        switch filter {
        case .open: base = store.pending
        case .completed: base = store.completedTasks
        case .all: base = store.pending + store.completedTasks
        }
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return base }
        return base.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.notes.localizedCaseInsensitiveContains(query) || $0.details.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            Picker("التصفية", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if items.isEmpty {
                EmptyStateCard(icon: "tray", title: "لا توجد مهام", message: "لا توجد مهام مطابقة.")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
            ForEach(items) { task in
                TaskRow(task: task) { editingTask = task }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { store.delete(task) } label: { Label("حذف", systemImage: "trash") }
                    }
                    .swipeActions(edge: .leading) {
                        Button { store.toggleCompletion(task) } label: {
                            Label(task.isCompleted ? "إعادة فتح" : "تم", systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
                        }
                        .tint(Brand.accent)
                    }
            }
        }
        .listStyle(.plain)
        .padding(.horizontal, 16)
        .background(Brand.canvas.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .searchable(text: $search, prompt: "ابحث في المهام")
        .navigationTitle("كل المهام")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingTask) { task in
            TaskEditorView(existingTask: task).environmentObject(store)
        }
    }
}
