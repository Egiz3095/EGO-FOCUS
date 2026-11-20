import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case home, calendar, reports, settings

    var title: String {
        switch self {
        case .home: return "الرئيسية"
        case .calendar: return "التقويم"
        case .reports: return "التقارير"
        case .settings: return "الإعدادات"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .calendar: return "calendar"
        case .reports: return "chart.bar.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Request to open the task editor for a new task (optionally on a given date).
struct NewTaskRequest: Identifiable {
    let id = UUID()
    var date: Date?
}

struct RootView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = AppTab(rawValue: LaunchOptions.initialTab ?? "") ?? .home
    @State private var newTask: NewTaskRequest?
    @State private var showAssistant = false
    @State private var openedTask: TaskRecord?

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(onAdd: { newTask = NewTaskRequest(date: nil) },
                     onAssistant: { showAssistant = true })
                .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.icon) }
                .tag(AppTab.home)

            CalendarView(onAdd: { date in newTask = NewTaskRequest(date: date) })
                .tabItem { Label(AppTab.calendar.title, systemImage: AppTab.calendar.icon) }
                .tag(AppTab.calendar)

            ReportsView()
                .tabItem { Label(AppTab.reports.title, systemImage: AppTab.reports.icon) }
                .tag(AppTab.reports)

            SettingsView()
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.icon) }
                .tag(AppTab.settings)
        }
        .sheet(item: $newTask) { request in
            TaskEditorView(existingTask: nil, initialDate: request.date)
                .environmentObject(store)
        }
        .sheet(isPresented: $showAssistant) {
            AssistantView().environmentObject(store)
        }
        .sheet(item: $openedTask) { task in
            TaskEditorView(existingTask: task).environmentObject(store)
        }
        .onReceive(NotificationCenter.default.publisher(for: .egoOpenTask)) { note in
            guard let id = note.object as? UUID else { return }
            store.refresh()
            if let task = store.task(id: id) {
                selectedTab = .home
                openedTask = task
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.refresh()
                store.syncNotifications()
            }
        }
        .onAppear {
            if LaunchOptions.openAssistant { showAssistant = true }
            if LaunchOptions.openEditor {
                if let first = store.pending.first { openedTask = first } else { newTask = NewTaskRequest(date: nil) }
            }
        }
    }
}
