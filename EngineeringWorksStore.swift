import SwiftUI
import SwiftData

// MARK: - Engineering Works Store
// Keeps the coming week's planned works from the feed, and how each saved route runs, on the
// phone; works out which works touch which saved route; and hands those to the views and to
// the alerts. The feed is read at most every three hours, and each route's path about once a
// month. Like the rest of the app's own work, this happens when the app is open or iOS wakes it.

@MainActor
@Observable
final class EngineeringWorksStore {

    static let shared = EngineeringWorksStore()
    private init() {}

    /// How far ahead the user is warned
    static let lookAhead: TimeInterval = 7 * 24 * 3600
    private static let feedInterval: TimeInterval = 3 * 3600
    private static let profileLifetime: TimeInterval = 30 * 24 * 3600

    /// The works on each saved route in the coming week, soonest first, by `key(_:_:)`
    private(set) var matches: [String: [EngineeringWork]] = [:]

    @ObservationIgnored private var cache = Cache()
    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private var isRefreshing = false
    /// A failed read is tried again after a while, not on every sync
    @ObservationIgnored private var lastFeedAttempt: Date?
    @ObservationIgnored private var lastProfileAttempt: [String: Date] = [:]
    /// What the matches were last worked out from, so an unchanged minute costs nothing
    @ObservationIgnored private var matchedFrom = ""
    @ObservationIgnored private lazy var names = StationNames(ukStations)

    private struct Cache: Codable {
        var fetched: Date?
        var works: [EngineeringWork] = []
        /// By `key(_:_:)`
        var profiles: [String: RouteProfile] = [:]
    }

    private static var cacheURL: URL {
        URL.applicationSupportDirectory.appending(path: "EngineeringWorks.json")
    }

    /// A route and its way back run on the same tracks, so they share a key.
    static func key(_ a: String, _ b: String) -> String {
        a < b ? "\(a)-\(b)" : "\(b)-\(a)"
    }

    /// The works in the coming week on the saved route between two stations, either way round.
    func works(between a: String, and b: String) -> [EngineeringWork] {
        matches[Self.key(a, b)] ?? []
    }

    // MARK: - Refresh

    /// `force` matches again even if nothing seems to have changed: after notification
    /// permission or the switch in Profile changes.
    func refresh(in context: ModelContext, force: Bool = false) async {
        if force { matchedFrom = "" }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if !isLoaded {
            load()
            isLoaded = true
        }

        let now = Date()
        await fetchFeedIfDue(now: now)
        await fetchProfiles(for: routes(in: context), now: now)

        // Fetched again: a route may have been saved or removed while the requests were out
        let routes = routes(in: context)
        let signature = [
            "\(cache.fetched?.timeIntervalSince1970 ?? 0)",
            // The week ahead moves on: match again every hour
            "\(Int(now.timeIntervalSince1970 / 3600))",
            "\(TrainAlerts.Kind.engineeringWorks.isOn)"
        ] + routes.map { "\($0.originCRS)\($0.destinationCRS)\($0.commuteDays)\(cache.profiles[Self.key($0.originCRS, $0.destinationCRS)] != nil)" }
        let joined = signature.joined(separator: "|")
        guard joined != matchedFrom else { return }
        matchedFrom = joined

        let found = match(routes, now: now)
        if found != matches { matches = found }
        await TrainAlerts.shared.refreshEngineeringWorksAlerts(alerts(for: routes))
    }

    private func routes(in context: ModelContext) -> [SavedRoute] {
        (try? context.fetch(FetchDescriptor<SavedRoute>())) ?? []
    }

    private func fetchFeedIfDue(now: Date) async {
        if let fetched = cache.fetched, now.timeIntervalSince(fetched) < Self.feedInterval { return }
        if let last = lastFeedAttempt, now.timeIntervalSince(last) < 15 * 60 { return }
        lastFeedAttempt = now

        let key = Secrets.knowledgebaseKey
        guard !key.isEmpty, !key.hasPrefix("YOUR_") else { return }

        var request = URLRequest(url: EngineeringWorksFeed.endpoint)
        request.setValue(key, forHTTPHeaderField: "x-apikey")
        request.timeoutInterval = 30
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }

        // About 3 MB of XML once unpacked: read it off the main thread
        guard let works = await Task.detached(priority: .utility, operation: { EngineeringWorksFeed.works(in: data) }).value else { return }

        // Only what could fall in the week ahead before the next read
        let horizon = now.addingTimeInterval(Self.lookAhead + 24 * 3600)
        cache.works = works.filter { $0.overlaps(from: now, to: horizon) }.sorted { $0.start < $1.start }
        cache.fetched = now
        save()
    }

    /// Asks the planner how each saved route runs, for those not asked lately. A few at a time:
    /// the planner is a shared, free service.
    private func fetchProfiles(for routes: [SavedRoute], now: Date) async {
        var asked = 0
        for route in routes {
            let key = Self.key(route.originCRS, route.destinationCRS)
            if let profile = cache.profiles[key], now.timeIntervalSince(profile.fetched) < Self.profileLifetime { continue }
            if let last = lastProfileAttempt[key], now.timeIntervalSince(last) < 3600 { continue }
            guard asked < 2, let origin = route.origin, let destination = route.destination else { continue }
            asked += 1
            lastProfileAttempt[key] = now

            if let profile = await JourneyPlanner.shared.routeProfile(from: origin, to: destination) {
                cache.profiles[key] = profile
                save()
            }
        }
    }

    // MARK: - Matching

    private func match(_ routes: [SavedRoute], now: Date) -> [String: [EngineeringWork]] {
        let places = Dictionary(cache.works.map { ($0.id, EngineeringWorksMatcher.places(of: $0, names: names)) }, uniquingKeysWith: { first, _ in first })

        var result: [String: [EngineeringWork]] = [:]
        for route in routes {
            let key = Self.key(route.originCRS, route.destinationCRS)
            // Without knowing how the route runs, a guess would warn about too much
            guard let origin = route.origin, let destination = route.destination,
                  let profile = cache.profiles[key] else { continue }

            let windows = windows(for: route, now: now)
            for work in cache.works where !(result[key]?.contains(work) ?? false) {
                guard windows.contains(where: { work.overlaps(from: $0.from, to: $0.to) }),
                      EngineeringWorksMatcher.work(work, places: places[work.id] ?? WorkPlaces(), affects: profile, origin: origin, destination: destination) else { continue }
                result[key, default: []].append(work)
            }
        }
        return result.mapValues { $0.sorted { $0.start < $1.start } }
    }

    /// When the route is travelled in the week ahead: all of it, or only the commute days.
    private func windows(for route: SavedRoute, now: Date) -> [(from: Date, to: Date)] {
        let end = now.addingTimeInterval(Self.lookAhead)
        guard route.isCommute else { return [(now, end)] }

        let calendar = SavedRoute.ukCalendar
        let today = calendar.startOfDay(for: now)
        return (0...7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  route.commutes(onWeekday: calendar.component(.weekday, from: day)),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            let from = max(day, now), to = min(next, end)
            return from < to ? (from, to) : nil
        }
    }

    /// One alert per work, named after the first saved route it is on, soonest first.
    private func alerts(for routes: [SavedRoute]) -> [(work: EngineeringWork, route: String)] {
        var seen: Set<String> = []
        var alerts: [(work: EngineeringWork, route: String)] = []
        for route in routes {
            for work in works(between: route.originCRS, and: route.destinationCRS) where seen.insert(work.id).inserted {
                alerts.append((work, "\(UKStation.name(for: route.originCRS)) to \(UKStation.name(for: route.destinationCRS))"))
            }
        }
        return alerts.sorted { $0.work.start < $1.work.start }
    }

    // MARK: - Storage

    private func load() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let saved = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        cache = saved
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try? data.write(to: Self.cacheURL, options: .atomic)
    }
}

// MARK: - Views

/// A line under a saved route when works are coming: "Engineering works · Sun 18 Oct"
struct EngineeringWorksBadge: View {
    let originCRS: String
    let destinationCRS: String

    var body: some View {
        let works = EngineeringWorksStore.shared.works(between: originCRS, and: destinationCRS)
        if let first = works.first {
            Label(
                works.count == 1 ? "Engineering works · \(first.whenText())" : "\(works.count) engineering works",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.statusDelayed)
            .lineLimit(1)
        }
    }
}

/// The works on a saved route, above its search results.
struct EngineeringWorksCard: View {
    let originCRS: String
    let destinationCRS: String

    var body: some View {
        let works = EngineeringWorksStore.shared.works(between: originCRS, and: destinationCRS)
        if !works.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Engineering works this week", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.statusDelayed)

                ForEach(works) { work in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(work.whenText())
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.ink)
                        Text(work.summary)
                            .font(.footnote)
                            .foregroundStyle(Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let link = work.link {
                            Link("Details on National Rail", destination: link)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.brand)
                        }
                    }
                    if work != works.last {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .noticeSurface(Color.statusDelayed)
        }
    }
}
