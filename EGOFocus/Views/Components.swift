import SwiftUI
import UIKit

enum Brand {
    static let accent = Color("AccentColor")
    static let ink = Color("BrandInk")
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let heroGradient = LinearGradient(
        colors: [Color(red: 0.06, green: 0.10, blue: 0.17), Color(red: 0.07, green: 0.29, blue: 0.32)],
        startPoint: .topTrailing, endPoint: .bottomLeading)

    static func color(for priority: TaskPriority) -> Color {
        switch priority {
        case .low: return .gray
        case .normal: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }
}

/// Applies the appearance setting to every window (covers sheets and system controls too).
enum AppearanceController {
    @MainActor static func apply(_ value: String) {
        let style: UIUserInterfaceStyle
        switch value {
        case "light": style = .light
        case "dark": style = .dark
        default: style = .unspecified
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows { window.overrideUserInterfaceStyle = style }
        }
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}

struct SectionHeader: View {
    let title: String
    var count: Int? = nil
    var tint: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }
}

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Brand.accent)
                .frame(width: 48, height: 48)
                .background(Brand.accent.opacity(0.12), in: Circle())
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22).padding(.horizontal, 16)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct PriorityBadge: View {
    let priority: TaskPriority

    var body: some View {
        Label(priority.rawValue, systemImage: priority.symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Brand.color(for: priority))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Brand.color(for: priority).opacity(0.14), in: Capsule())
            .accessibilityLabel("الأولوية: \(priority.rawValue)")
    }
}

struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 8
    var tint: Color = .white
    var track: Color = .white.opacity(0.2)

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: progress)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

struct AddTaskButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Brand.accent, in: Circle())
                .shadow(color: Brand.accent.opacity(0.35), radius: 12, y: 6)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 16)
        .accessibilityLabel("إضافة مهمة")
        .accessibilityIdentifier("addTaskButton")
    }
}

struct TaskRow: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskRecord
    /// Occurrence date to display (calendar projections); defaults to the task's due date.
    var displayDate: Date? = nil
    var isProjection = false
    var showsDay = true
    var onEdit: (() -> Void)? = nil

    var body: some View {
        let date = displayDate ?? task.dueDate
        let overdue = !isProjection && task.isOverdue(now: store.now)
        HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation(.snappy) { store.toggleCompletion(task) }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.isCompleted ? Brand.accent : Brand.color(for: task.priority).opacity(0.85))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isProjection)
            .accessibilityLabel(task.isCompleted ? "إعادة فتح \(task.title)" : "إكمال \(task.title)")

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.body.weight(.semibold))
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !task.details.isEmpty {
                    Text(task.details)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                metaRow(date: date, overdue: overdue)
            }
            Spacer(minLength: 0)
            if task.priority == .high || task.priority == .urgent, !task.isCompleted {
                PriorityBadge(priority: task.priority)
            }
        }
        .padding(.vertical, 12)
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Brand.color(for: task.priority).opacity(task.isCompleted ? 0.3 : 1))
                .frame(width: 4)
                .padding(.vertical, 14)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { onEdit?() }
        .contextMenu {
            if !isProjection {
                Button { store.toggleCompletion(task) } label: {
                    Label(task.isCompleted ? "إعادة فتح" : "تم التنفيذ",
                          systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
                }
            }
            Button { onEdit?() } label: { Label("تعديل", systemImage: "pencil") }
            Button(role: .destructive) { store.delete(task) } label: {
                Label("حذف المهمة", systemImage: "trash")
            }
        }
    }

    private func metaRow(date: Date, overdue: Bool) -> some View {
        let calendar = AppCalendar.calendar
        let dateText = showsDay && !calendar.isDate(date, inSameDayAs: store.now)
            ? AppFormat.dateTimeShort(date) : AppFormat.time(date)
        return HStack(spacing: 10) {
            Label(dateText, systemImage: overdue ? "exclamationmark.circle" : "clock")
                .foregroundStyle(overdue ? Color.red : Color.secondary)
            Label(task.category.rawValue, systemImage: task.category.symbol)
            if task.recurrence != .none {
                Label(task.recurrence.rawValue, systemImage: "repeat")
            }
            if !task.reminderOffsets.isEmpty && !task.isCompleted {
                Image(systemName: "bell")
                    .accessibilityLabel("تذكير مفعّل")
            }
        }
        .labelStyle(CompactLabelStyle())
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}
