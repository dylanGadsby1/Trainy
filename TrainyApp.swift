import SwiftUI
import SwiftData
import UserNotifications

@main
struct TrainyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        UNUserNotificationCenter.current().delegate = TrainAlerts.shared
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SavedTrain.self,
            SavedRoute.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
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
