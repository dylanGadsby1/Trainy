import Foundation
import ActivityKit

struct TrainyActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var scheduledDeparture: String
        var expectedDeparture: String
        var delayMinutes: Int
        var platform: String
        var isCancelled: Bool
        /// On a journey of several trains, the train the rest is about: "York to Durham".
        /// Nil when the activity follows a single train.
        var legSummary: String?
        /// On a journey of several trains, what follows this train:
        /// "Change at York · 7 min · Platform 11", or "Arrive Durham 14:07"
        var nextStep: String?
    }

    var trainId: String
    var originName: String
    var originCRS: String
    var destinationName: String
    var destinationCRS: String
    var operatorCode: String
}
