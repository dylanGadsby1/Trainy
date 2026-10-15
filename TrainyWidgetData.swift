import Foundation

// MARK: - Widget Data
// What the Home Screen and Lock Screen widgets show. The app writes it on every sync into the
// App Group it shares with the widget extension, and the widget reads it from there. Compiled
// into both targets, like TrainyActivityAttributes.

enum TrainyWidgetData {

    /// Also under com.apple.security.application-groups in both targets' entitlements
    static let appGroup = "group.com.dylangadsby.Trainy"

    /// The widget's kind, for asking WidgetKit to reload it
    static let kind = "NextTrain"

    private static let key = "widget.trains"

    /// One saved train, reduced to what a widget shows
    struct Train: Codable, Hashable, Identifiable {
        /// The train's journey key
        var id: String
        var originCRS: String
        var originName: String
        var destinationCRS: String
        var destinationName: String
        /// "HH:mm"
        var scheduledDeparture: String
        var expectedDeparture: String
        /// When the train is now expected to leave the user's station
        var departs: Date
        /// When it is now expected at the user's destination, if known
        var arrives: Date?
        /// "HH:mm"
        var expectedArrival: String?
        /// Nil until a platform is given
        var platform: String?
        /// The platform came from a live feed, not only the timetable
        var platformConfirmed: Bool
        var delayMinutes: Int
        var isCancelled: Bool
        /// Delayed, with no new time given yet
        var hasUnknownDelay: Bool
        /// Only the timetable is known so far
        var isScheduled: Bool
        var operatorName: String?
        /// On a journey with a change: where the next change is, "York"
        var changeAt: String?
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    /// The saved trains still to come, soonest first. Empty when the App Group is unavailable.
    static func load() -> [Train] {
        guard let data = defaults?.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Train].self, from: data)) ?? []
    }

    /// Stores `trains` for the widget. Returns false when nothing changed, so the widget need not reload.
    @discardableResult
    static func save(_ trains: [Train]) -> Bool {
        guard let defaults, let data = try? JSONEncoder().encode(trains),
              data != defaults.data(forKey: key) else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}
