import SwiftUI
import SwiftData

// MARK: - Live Disruptions
// What is going wrong on the railway right now, from National Rail's Disruptions API on the
// Rail Data Marketplace, matched to the trains in My Trains.
//
// The API lists a disruption at every station its operator's trains call at, so York shows a
// CrossCountry problem near Birmingham. A disruption only counts for a train of an operator it
// names, and how sure the match is decides how loud it is:
//   on the route    its summary names a stretch the user's journey runs along: shown and notified
//   on the operator only its list of affected services covers the train, which can be delayed
//                   by trouble far away: shown, quietly, and not notified

/// One disruption from the feed, cut down to what the app shows and matches on.
struct LiveDisruption: Codable, Hashable, Identifiable {
    let id: String
    /// "Disruption between Birmingham New Street and Leicester / Derby expected until 20:00"
    let summary: String
    /// The services it touches, in words: "Between Plymouth and Leeds / Newcastle / Edinburgh, …"
    let routesAffected: String
    /// Two-letter operator codes
    let operators: [String]
    let isPlanned: Bool
    let link: URL?

    /// The same thing as a planned work, for the matching engineering works already use.
    var asWork: EngineeringWork {
        EngineeringWork(id: id, start: .distantPast, end: nil, summary: summary,
                        routesAffected: routesAffected, operators: operators, link: link)
    }
}

/// A disruption that affects one of the user's trains.
struct TrainDisruption: Hashable, Identifiable {
    let disruption: LiveDisruption
    /// Its summary names a stretch the user's journey runs along, not only the operator's services
    let isOnRoute: Bool

    var id: String { disruption.id }
}

@MainActor
@Observable
final class LiveDisruptions {

    static let shared = LiveDisruptions()
    private init() {}

    private static let endpoint = "https://api1.raildata.org.uk/1010-disruptions-experience-api-11_1/stations/disruptions/incidents"
    /// Disruptions change by the minute, but not every minute matters
    private static let interval: TimeInterval = 3 * 60
    /// Trains further off than this are not worth asking about yet
    private static let lookAhead: TimeInterval = 12 * 3600

    /// The disruptions on each followed train, by its `journeyKey`, the surest first
    private(set) var matches: [String: [TrainDisruption]] = [:]

    @ObservationIgnored private var lastFetch: Date?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private lazy var names = StationNames(ukStations)

    func disruptions(for train: DarwinServiceAdapter) -> [TrainDisruption] {
        matches[train.journeyKey] ?? []
    }

    /// Reads the disruptions at the stations of the trains still to run or running, at most
    /// every few minutes, and works out which affect which train.
    func refresh(_ savedTrains: [SavedTrain], now: Date = Date()) async {
        guard !isRefreshing else { return }
        if let lastFetch, now.timeIntervalSince(lastFetch) < Self.interval { return }

        let trains = savedTrains.filter { !$0.isPast && !$0.isDeleted }.compactMap(\.service).filter { train in
            guard !train.isCancelledService, train.hasArrived != true,
                  let departure = train.expectedDepartureDate ?? train.scheduledDepartureDate else { return false }
            return departure.timeIntervalSince(now) < Self.lookAhead
        }
        guard !trains.isEmpty else {
            if !matches.isEmpty { matches = [:] }
            return
        }

        let key = Secrets.disruptionsKey
        guard !key.isEmpty, !key.hasPrefix("YOUR_") else { return }

        isRefreshing = true
        defer { isRefreshing = false }
        lastFetch = now

        // The API takes up to ten stations a request
        let stations = Array(Set(trains.flatMap { [$0.userSearchOriginCRS ?? $0.originCRS, $0.userSearchDestinationCRS ?? $0.destinationCRS] })).sorted()
        var byID: [String: LiveDisruption] = [:]
        for start in stride(from: 0, to: stations.count, by: 10) {
            var components = URLComponents(string: Self.endpoint)!
            components.queryItems = [URLQueryItem(name: "crsCode", value: stations[start..<min(start + 10, stations.count)].joined(separator: ","))]
            var request = URLRequest(url: components.url!)
            request.setValue(key, forHTTPHeaderField: "x-apikey")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15

            // A failed read keeps what was found before, rather than clearing every warning
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let feed = try? JSONDecoder().decode([Feed.Station].self, from: data) else { return }

            for station in feed {
                for item in station.disruptions where item.status.map({ $0.caseInsensitiveCompare("Active") == .orderedSame }) ?? true {
                    byID[item.id] = item.disruption
                }
            }
        }

        var found: [String: [TrainDisruption]] = [:]
        for train in trains {
            let matched = byID.values.compactMap { match($0, to: train) }
                .sorted { ($0.isOnRoute ? 0 : 1, $0.disruption.summary) < ($1.isOnRoute ? 0 : 1, $1.disruption.summary) }
            if !matched.isEmpty { found[train.journeyKey] = matched }
        }
        if found != matches { matches = found }

        for train in trains {
            for item in found[train.journeyKey] ?? [] where item.isOnRoute {
                TrainAlerts.shared.disruptionFound(item.disruption, on: train)
            }
        }
    }

    /// Nil when `disruption` does not touch `train`.
    private func match(_ disruption: LiveDisruption, to train: DarwinServiceAdapter) -> TrainDisruption? {
        guard let operatorCode = train.atocCode, disruption.operators.contains(operatorCode),
              let origin = ukStations.first(where: { $0.crs == (train.userSearchOriginCRS ?? train.originCRS) }),
              let destination = ukStations.first(where: { $0.crs == (train.userSearchDestinationCRS ?? train.destinationCRS) }) else { return nil }

        // The train's own path, as a route the engineering works matching understands
        let profile = RouteProfile(
            lines: train.routeLine.map { [$0] } ?? [],
            stations: (train.stops ?? []).map(\.crs),
            operators: [operatorCode],
            fetched: Date()
        )
        let work = disruption.asWork

        // Where the trouble is, from the summary
        let summaryPlaces = names.places(in: work.summary)
        if !summaryPlaces.isEmpty,
           EngineeringWorksMatcher.work(work, places: summaryPlaces, affects: profile, origin: origin, destination: destination) {
            return TrainDisruption(disruption: disruption, isOnRoute: true)
        }
        // Which services it touches: a train coming from far away can be late because of it
        let routePlaces = names.places(in: work.routesAffected)
        if EngineeringWorksMatcher.work(work, places: routePlaces, affects: profile, origin: origin, destination: destination) {
            return TrainDisruption(disruption: disruption, isOnRoute: false)
        }
        return nil
    }

    /// The parts of the feed the app reads.
    private enum Feed {
        struct Station: Decodable {
            var crsCode: String?
            var disruptions: [Item]
        }

        struct Item: Decodable {
            var id: String
            var summary: String?
            var status: String?
            var isPlanned: Bool?
            var affectedOperators: [Operator]?
            var affectedRoutes: [Route]?
            var disruptionLinks: [Link]?

            struct Operator: Decodable { var tocCode: String? }
            struct Route: Decodable { var routeDetails: String? }
            struct Link: Decodable { var uri: String? }

            var disruption: LiveDisruption {
                LiveDisruption(
                    id: id,
                    summary: EngineeringWorksFeed.plainText(summary ?? ""),
                    routesAffected: EngineeringWorksFeed.plainText((affectedRoutes ?? []).compactMap(\.routeDetails).joined(separator: " ")),
                    operators: (affectedOperators ?? []).compactMap(\.tocCode),
                    isPlanned: isPlanned ?? false,
                    link: disruptionLinks?.first?.uri.flatMap(URL.init(string:))
                )
            }
        }
    }
}

// MARK: - Views

/// The disruptions affecting a followed train, or any train of a journey.
struct DisruptionsCard: View {
    let trains: [DarwinServiceAdapter]

    var body: some View {
        let store = LiveDisruptions.shared
        // A disruption on two trains of a journey is shown once
        var seen = Set<String>()
        let items = trains.flatMap { store.disruptions(for: $0) }.filter { seen.insert($0.id).inserted }
            .sorted { ($0.isOnRoute ? 0 : 1) < ($1.isOnRoute ? 0 : 1) }

        if !items.isEmpty {
            let color = items.contains(where: \.isOnRoute) ? Color.statusCancelled : Color.statusDelayed
            VStack(alignment: .leading, spacing: 12) {
                Label(items.contains(where: \.isOnRoute) ? "Disruption on your route" : "Disruption that may affect your train",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)

                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.disruption.summary)
                            .font(.footnote.weight(item.isOnRoute ? .semibold : .regular))
                            .foregroundStyle(item.isOnRoute ? Color.ink : Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !item.isOnRoute {
                            Text("Elsewhere on the operator's routes, but it can delay trains coming through.")
                                .font(.caption)
                                .foregroundStyle(Color.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let link = item.disruption.link {
                            Link("Details on National Rail", destination: link)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.brand)
                        }
                    }
                    if item != items.last {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .noticeSurface(color)
        }
    }
}
