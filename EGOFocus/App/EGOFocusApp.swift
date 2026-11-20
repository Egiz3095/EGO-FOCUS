import SwiftUI
import SwiftData
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        SettingsKey.registerDefaults()
        // Set the notification delegate before launch completes so actions are handled
        // even when the app was not running.
        NotificationService.shared.configure()
        if LaunchOptions.isUITesting { UIView.setAnimationsEnabled(false) }
        return true
    }
}

@main
struct EGOFocusApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TaskStore(container: Persistence.shared)
    @AppStorage(SettingsKey.appearance) private var appearance = "system"

    init() {
        SettingsKey.registerDefaults()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, AppLocale.arabic)
                .environment(\.calendar, AppCalendar.calendar)
                .tint(Brand.accent)
                .onAppear { AppearanceController.apply(appearance) }
                .onChange(of: appearance) { _, value in AppearanceController.apply(value) }
                .task { await store.onLaunch() }
        }
        .modelContainer(Persistence.shared)
    }

}
