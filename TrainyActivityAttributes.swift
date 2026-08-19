import Foundation
import ActivityKit

struct TrainyActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var scheduledDeparture: String
        var expectedDeparture: String
        var delayMinutes: Int
        var platform: String
        var isCancelled: Bool
    }

    var trainId: String
    var originName: String
    var originCRS: String
    var destinationName: String
    var destinationCRS: String
    var operatorCode: String
}
