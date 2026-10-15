import SwiftUI
import SwiftData
import UserNotifications

@main
struct TrainyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        UNUserNotificationCenter.current().delegate = TrainAlerts.shared
        // After the store has opened, which decides whether iCloud is in use
        CloudSync.startSyncingPreferences(in: sharedModelContainer)
    }

    var sharedModelContainer: ModelContainer = CloudSync.makeContainer(for: Schema([
        SavedTrain.self,
        SavedRoute.self,
        SyncedSetting.self,
    ]))
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) { [sharedModelContainer] in
            await BackgroundRefresh.run(in: sharedModelContainer)
        }
    }
}
