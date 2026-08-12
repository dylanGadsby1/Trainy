import SwiftUI
import SwiftData

@main
struct TrainyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: SavedTrain.self)
    }
}
