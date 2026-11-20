import SwiftUI
import Charts

struct ReportsView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var period: ReportPeriod = .week

    var body: some View {
        let stats = store.stats(for: period)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("الفترة", selection: $period) {
                        ForEach(ReportPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("reports.period")

                    Text(rangeText(stats.interval))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    completionCard(stats)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        StatTile(title: "مهام مكتملة", value: "\(stats.completed)", icon: "checkmark.circle.fill", tint: Brand.accent)
                        StatTile(title: "قيد الانتظار", value: "\(stats.pending)", icon: "hourglass", tint: .blue)
                        StatTile(title: "متأخرة", value: "\(stats.overdue)", icon: "exclamationmark.circle.fill", tint: .red)
                        StatTile(title: "إجمالي مهام الفترة", value: "\(stats.total)", icon: "list.bullet.rectangle", tint: .orange)
                    }

                    if period != .day { chartCard }
                    categoryCard
                    overallCard
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
            .background(Brand.canvas.ignoresSafeArea())
            .navigationTitle("التقارير")
        }
    }

    private func rangeText(_ interval: DateInterval) -> String {
        switch period {
        case .day:
            return AppFormat.fullDate(interval.start)
        case .week, .month:
            let end = interval.end.addingTimeInterval(-1)
            return "من \(AppFormat.shortDay(interval.start)) إلى \(AppFormat.shortDay(end))"
        }
    }

    private func completionCard(_ stats: PeriodStats) -> some View {
        HStack(spacing: 18) {
            ZStack {
                ProgressRing(progress: stats.completionRate, lineWidth: 10, tint: Brand.accent, track: Brand.accent.opacity(0.15))
                Text(AppFormat.percent(stats.completionRate))
                    .font(.title3.weight(.bold).monospacedDigit())
            }
            .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 6) {
                Text("نسبة الإنجاز").font(.headline)
                Text(stats.total == 0
                     ? "لا توجد مهام مستحقة أو منجزة في هذه الفترة."
                     : "أنجزت \(stats.completed) من أصل \(stats.total) مهمة مستحقة أو منجزة خلال \(period.rawValue).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reports.completion")
    }

    private var chartCard: some View {
        let data = store.dailyCompletions(for: period)
        return VStack(alignment: .leading, spacing: 12) {
            Text("الإنجاز اليومي").font(.headline)
            Chart(data) { item in
                BarMark(x: .value("اليوم", item.day, unit: .day),
                        y: .value("المكتملة", item.count))
                    .foregroundStyle(Brand.accent.gradient)
                    .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                if period == .week {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) { Text(AppFormat.weekdayShort(date)) }
                        }
                    }
                } else {
                    AxisMarks(values: .stride(by: .day, count: 7)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) { Text(AppFormat.shortDay(date)) }
                        }
                    }
                }
            }
            .frame(height: 180)
        }
        .card()
    }

    private var categoryCard: some View {
        let rows = store.completionsByCategory(for: period)
        let maxValue = max(rows.map(\.1).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text("الإنجاز حسب التصنيف").font(.headline)
            if rows.isEmpty {
                Text("لم تُنجز مهام في هذه الفترة بعد.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(rows, id: \.0) { row in
                    let category = row.0
                    let count = row.1
                    HStack(spacing: 10) {
                        Label(category.rawValue, systemImage: category.symbol)
                            .font(.subheadline)
                            .frame(width: 92, alignment: .leading)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Brand.accent.opacity(0.85))
                                .frame(width: max(8, proxy.size.width * CGFloat(count) / CGFloat(maxValue)))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 10)
                        Text("\(count)").font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                }
            }
        }
        .card()
    }

    private var overallCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("نظرة عامة").font(.headline)
            row("كل المهام المسجلة", "\(store.tasks.count)")
            row("المهام المفتوحة", "\(store.pending.count)")
            row("المتأخرة حالياً", "\(store.overdue.count)")
            row("مرات الإنجاز المسجلة", "\(store.events.count)")
            row("نسبة الإنجاز الإجمالية", AppFormat.percent(store.overallCompletionRate))
        }
        .card()
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }
}
