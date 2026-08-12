import SwiftUI

@available(iOS 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
struct TestTab: View {
    var body: some View {
        TabView {
            Tab("My Trains", systemImage: "tram.fill", value: 0) {
                Text("Trains")
            }
        }
    }
}
