import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var store: TaskStore
    let onAdd: (Date) -> Void

    @State private var month: Date = RecurrenceEngine.startOfMonth(.now, AppCalendar.calendar)
    @State private var selectedDate: Date = AppCalendar.calendar.startOfDay(for: .now)
    @State private var editingTask: TaskRecord?

    private var calendar: Calendar { AppCalendar.calendar }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    monthHeader
                    monthGrid
                    dayHeader
                    dayList
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 90)
            }
            .background(Brand.canvas.ignoresSafeArea())
            .overlay(alignment: .bottomTrailing) { AddTaskButton { onAdd(selectedDate) } }
            .navigationTitle("التقويم")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("اليوم") { goToToday() }
                        .accessibilityIdentifier("calendar.today")
                }
            }
            .sheet(item: $editingTask) { task in
                TaskEditorView(existingTask: task).environmentObject(store)
            }
        }
    }

    // MARK: Month

    private var monthHeader: some View {
        HStack {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.backward")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(Brand.card, in: Circle())
            }
            .accessibilityLabel("الشهر السابق")
            Spacer()
            Text(AppFormat.monthYear(month))
                .font(.title3.weight(.bold))
                .accessibilityIdentifier("calendar.monthTitle")
            Spacer()
            Button { shift(1) } label: {
                Image(systemName: "chevron.forward")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(Brand.card, in: Circle())
            }
            .accessibilityLabel("الشهر التالي")
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var days: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let first = RecurrenceEngine.startOfMonth(month, calendar)
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let dates: [Date] = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: first) }
        let blanks: [Date?] = Array(repeating: nil, count: leading)
        return blanks + dates.map { Optional($0) }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                if let date { dayCell(date) } else { Color.clear.frame(height: 46) }
            }
        }
        .card(padding: 12)
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            // RTL: swiping toward the right shows the next month.
            if value.translation.width > 60 { shift(1) } else if value.translation.width < -60 { shift(-1) }
        })
    }

    private func dayCell(_ date: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDate(date, inSameDayAs: store.now)
        let indicator = store.indicatorPriority(on: date)
        return Button {
            withAnimation(.snappy) { selectedDate = date }
        } label: {
            VStack(spacing: 4) {
                Text(AppFormat.dayNumber(date))
                    .font(.subheadline.weight(selected || isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(selected ? Brand.onAccent : (isToday ? Brand.accent : Color.primary))
                Circle()
                    .fill(indicator.map { selected ? Brand.onAccent : Brand.color(for: $0) } ?? Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Brand.accent : Color.clear)
            }
            .overlay {
                if isToday && !selected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Brand.accent, lineWidth: 1.2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(AppFormat.fullDate(date))\(indicator == nil ? "" : "، توجد مهام")")
    }

    // MARK: Day

    private var dayHeader: some View {
        let count = store.items(on: selectedDate).count
        return SectionHeader(title: calendar.isDate(selectedDate, inSameDayAs: store.now) ? "مهام اليوم" : AppFormat.dayMonth(selectedDate),
                             count: count)
    }

    @ViewBuilder private var dayList: some View {
        let items = store.items(on: selectedDate)
        if items.isEmpty {
            EmptyStateCard(icon: "calendar", title: "لا توجد مهام في هذا اليوم",
                           message: "اضغط + لإضافة مهمة في \(AppFormat.dayMonth(selectedDate)).")
        } else {
            ForEach(items) { item in
                TaskRow(task: item.task, displayDate: item.date, isProjection: item.isProjection, showsDay: false) {
                    editingTask = item.task
                }
            }
            if items.contains(where: \.isProjection) {
                Label("المهام المتكررة تظهر في مواعيدها القادمة؛ يمكن إنجاز الموعد الحالي فقط.", systemImage: "repeat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func shift(_ amount: Int) {
        withAnimation(.snappy) {
            month = calendar.date(byAdding: .month, value: amount, to: month) ?? month
        }
    }

    private func goToToday() {
        withAnimation(.snappy) {
            month = RecurrenceEngine.startOfMonth(store.now, calendar)
            selectedDate = calendar.startOfDay(for: store.now)
        }
    }
}
