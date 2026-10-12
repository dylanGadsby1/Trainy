import SwiftUI
import SwiftData

@main
struct TrainyApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SavedTrain.self,
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
                // Cards and sheets are drawn on fixed white backgrounds, so dark mode
                // would put white text on white. Remove once the surfaces adapt.
                .preferredColorScheme(.light)
        }
        .modelContainer(sharedModelContainer)
    }
}
