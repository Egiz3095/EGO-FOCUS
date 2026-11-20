import Foundation
import SwiftData

/// Single on-disk SwiftData store shared by the UI and by notification actions
/// (which can run while the app is launched in the background).
enum Persistence {
    static let schema = Schema([TaskRecord.self, CompletionEvent.self])

    @MainActor static let shared: ModelContainer = makeAppContainer()

    @MainActor private static func makeAppContainer() -> ModelContainer {
        // Explicitly local: no CloudKit, no app group, persisted on disk.
        let configuration = ModelConfiguration("EGOFocus",
                                               schema: schema,
                                               isStoredInMemoryOnly: false,
                                               allowsSave: true,
                                               groupContainer: .none,
                                               cloudKitDatabase: .none)
        if LaunchOptions.resetStore {
            removeStoreFiles(at: configuration.url)
            UserDefaults.standard.removeObject(forKey: SettingsKey.dailyBriefEnabled)
        }
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("EGO FOCUS: تعذر فتح قاعدة البيانات المحلية — \(error)")
        }
    }

    /// On-disk container at an explicit URL (used by persistence tests).
    static func makeContainer(storeURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, url: storeURL, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// In-memory container — only for unit tests and previews, never the app's primary store.
    static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func removeStoreFiles(at url: URL) {
        let manager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let path = url.path + suffix
            if manager.fileExists(atPath: path) { try? manager.removeItem(atPath: path) }
        }
    }
}
