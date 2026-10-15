import Foundation
import SwiftData
import UIKit

// MARK: - Trainy Server
// Optional. With a server address under TrainyServerURL in Info.plist (see server/README.md):
//   - both feeds are read through the server, so their keys need not ship in the app
//   - the app registers for push and tells the server which trains to follow, so alerts
//     and the Live Activity keep up while the app is closed
// Without one the app reads the feeds itself and raises its own alerts (TrainAlerts).

@MainActor
final class TrainyServer {

    static let shared = TrainyServer()
    private init() {}

    /// Nil when no server is configured
    nonisolated static let baseURL: URL? = {
        guard let address = Bundle.main.object(forInfoDictionaryKey: "TrainyServerURL") as? String,
              !address.isEmpty else { return nil }
        return URL(string: address)
    }()

    /// Sent with every request. It ships in the app, so it only turns away casual callers.
    private nonisolated static let appKey = Bundle.main.object(forInfoDictionaryKey: "TrainyServerKey") as? String

    /// A request to the server for `path`, such as "darwin/GetDepartureBoard/EUS".
    nonisolated static func request(_ path: String, query: [URLQueryItem] = []) -> URLRequest? {
        guard let baseURL,
              var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else { return nil }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let appKey, !appKey.isEmpty {
            request.setValue(appKey, forHTTPHeaderField: "x-trainy-key")
        }
        return request
    }

    // MARK: - Push

    /// This device's address for push notifications, once iOS has given one
    var deviceToken: String? {
        didSet { resync() }
    }

    /// The Live Activity's address for push updates, and the journey it is showing
    private(set) var liveActivity: (journeyKey: String, token: String)?

    /// True once the server has taken on this device's trains. It sends the alerts from
    /// then on, so the app stops raising its own.
    private(set) var isWatching = false

    /// A Live Activity can only be updated by push once the device has registered for it
    var canPushLiveActivities: Bool {
        Self.baseURL != nil && deviceToken != nil
    }

    private var container: ModelContainer?
    /// What the server was last told, so it only hears from the app when something changes
    private var lastRegistration: Data?

    func setLiveActivity(journeyKey: String, token: String?) {
        liveActivity = token.map { (journeyKey, $0) }
        resync()
    }

    private func resync() {
        guard let container else { return }
        Task { await sync(in: container.mainContext) }
    }

    /// Tells the server which trains this device is following.
    func sync(in context: ModelContext) async {
        guard Self.baseURL != nil else { return }
        container = context.container

        guard TrainAlerts.shared.isAllowed else {
            // Without permission nothing can be shown, so there is nothing to watch for
            if isWatching { await forget() }
            return
        }
        guard let deviceToken else {
            // Answered through the app delegate. Fails harmlessly without the push entitlement.
            UIApplication.shared.registerForRemoteNotifications()
            return
        }

        let upcoming = FetchDescriptor<SavedTrain>(predicate: #Predicate { !$0.isPast })
        let trains = (try? context.fetch(upcoming)) ?? []
        let registration = Registration(
            environment: Self.environment,
            alerts: .init(
                delays: TrainAlerts.Kind.delays.isOn,
                platforms: TrainAlerts.Kind.platforms.isOn,
                departures: TrainAlerts.Kind.departures.isOn
            ),
            trains: trains.compactMap { saved in
                saved.service.flatMap { Registration.Train($0, remind: saved.remindsBeforeDeparture, liveActivity: liveActivity) }
            }
        )

        // The server keeps its own record of each train's times, so only a change to
        // which trains are followed, or how, is worth sending
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let signature = try? encoder.encode(registration.withoutState),
              signature != lastRegistration,
              var request = Self.request("v1/devices/\(deviceToken)"),
              let body = try? encoder.encode(registration) else { return }

        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let status = (try? await URLSession.shared.data(for: request)).flatMap { ($0.1 as? HTTPURLResponse)?.statusCode }
        isWatching = status == 200
        lastRegistration = isWatching ? signature : nil
    }

    /// Removes this device from the server.
    func forget() async {
        isWatching = false
        lastRegistration = nil
        guard let deviceToken, var request = Self.request("v1/devices/\(deviceToken)") else { return }
        request.httpMethod = "DELETE"
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Builds from Xcode get their pushes from Apple's sandbox
    private static var environment: String {
        #if DEBUG
        "development"
        #else
        "production"
        #endif
    }
}

// MARK: - Registration

/// What the server is told about this device. The field names are the server's.
private struct Registration: Encodable {
    var environment: String
    var alerts: Alerts
    var trains: [Train]

    struct Alerts: Encodable {
        var delays: Bool
        var platforms: Bool
        var departures: Bool
    }

    struct Train: Encodable {
        var key: String
        /// The Darwin id, when the train has one
        var serviceID: String?
        var origin: String
        var destination: String
        var originName: String
        var destinationName: String
        var departureDate: String
        var scheduledDeparture: String
        var scheduledArrival: String?
        var operatorCode: String?
        var liveActivityToken: String?
        /// Gets the reminders an hour and five minutes before it leaves
        var remind: Bool
        var state: State?

        struct State: Encodable {
            var expectedDeparture: String
            var expectedArrival: String?
            var platform: String
            var platformConfirmed: Bool
            var delayMinutes: Int
            var isCancelled: Bool
            var hasUnknownDelay: Bool
            var hasArrived: Bool
        }

        init?(_ train: DarwinServiceAdapter, remind: Bool, liveActivity: (journeyKey: String, token: String)?) {
            guard let departureDate = train.scheduleMetadata?.departureDate else { return nil }
            let origin = train.userSearchOriginCRS ?? train.originCRS
            let destination = train.userSearchDestinationCRS ?? train.destinationCRS

            self.key = train.journeyKey
            self.serviceID = train.dataSource == .rtt ? nil : train.serviceID
            self.origin = origin
            self.destination = destination
            self.originName = ukStations.first { $0.crs == origin }?.name ?? origin
            self.destinationName = ukStations.first { $0.crs == destination }?.name ?? destination
            self.departureDate = departureDate
            self.scheduledDeparture = train.scheduledDeparture
            self.scheduledArrival = train.userSearchDestinationScheduledArrivalTime
            self.operatorCode = train.atocCode
            self.liveActivityToken = liveActivity?.journeyKey == train.journeyKey ? liveActivity?.token : nil
            self.remind = remind
            self.state = State(
                expectedDeparture: train.realtimeDeparture,
                expectedArrival: train.userSearchDestinationArrivalTime,
                platform: train.platform,
                platformConfirmed: train.hasConfirmedPlatform,
                delayMinutes: train.delayMinutes,
                isCancelled: train.isCancelledService,
                hasUnknownDelay: train.hasUnknownDelay == true,
                hasArrived: train.hasArrived == true
            )
        }
    }

    var withoutState: Registration {
        var copy = self
        copy.trains = trains.map {
            var train = $0
            train.state = nil
            return train
        }
        return copy
    }
}

// MARK: - App Delegate

/// Receives the device's push address, which only arrives through an app delegate.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        TrainyServer.shared.deviceToken = deviceToken.map { String(format: "%02x", $0) }.joined()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // No push entitlement, or no connection: the app carries on raising its own alerts
        print("Push registration failed: \(error.localizedDescription)")
    }
}
