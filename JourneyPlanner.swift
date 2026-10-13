import Foundation
import CoreLocation
import SwiftData

// MARK: - Journey Planner
// Neither train feed can plan a journey: each only lists the direct trains between two
// stations. Routes with a change come from Transitous (transitous.org), a planner run by
// volunteers over open timetable data. It only suggests the route. Each train on it is then
// followed through Darwin and Realtime Trains like any other train in the app.
//
// Transitous is free and has no key. In return it asks that an app says who it is, asks only
// when it has to, and links to its data sources where the routes are shown.

/// One train on a planned journey, between the stations where the traveller boards and leaves it.
struct PlannedLeg: Hashable {
    var originCRS: String
    var destinationCRS: String
    /// Where the train itself starts and ends its run
    var trainOriginName: String
    var trainDestinationName: String

    var scheduledDeparture: Date
    var expectedDeparture: Date
    var scheduledArrival: Date
    var expectedArrival: Date

    var operatorCode: String?
    var operatorName: String?
    var platform: String?
    /// The platform the train is timetabled into, where the traveller leaves it
    var arrivalPlatform: String?
    var stops: [Stop]

    struct Stop: Hashable {
        var crs: String
        var name: String
        var scheduled: Date
        var expected: Date
        var isCancelled: Bool
    }

    var originName: String { UKStation.name(for: originCRS) }
    var destinationName: String { UKStation.name(for: destinationCRS) }

    /// Tells one train from another across plans: the same train reached a different way is one train.
    var key: String {
        "\(originCRS)-\(destinationCRS)-\(Int(scheduledDeparture.timeIntervalSince1970))"
    }
}

/// What the traveller does between two trains, before the first or after the last.
struct PlannedTransfer: Hashable {
    enum Kind: Hashable {
        /// Another platform at the same station
        case change
        case walk
        /// The Tube, a tram or a metro
        case ride
    }

    var kind: Kind
    /// "Change at Birmingham New Street", "Tube from Euston to Victoria"
    var text: String
    /// How long the planner allows for it
    var minutes: Int
    /// The Tube lines it uses, when it is a ride on the Underground
    var tubeLines: [String] = []

    var systemImage: String {
        switch kind {
        case .change: return "arrow.triangle.swap"
        case .walk: return "figure.walk"
        case .ride: return "tram.fill"
        }
    }
}

/// A route from one station to another that is more than one direct train.
struct PlannedJourney: Identifiable, Hashable {
    enum Part: Hashable {
        case train(PlannedLeg)
        case transfer(PlannedTransfer)
    }

    /// "Newcastle to Bristol Temple Meads": the stations that were searched for
    var title: String
    var parts: [Part]
    /// When the traveller sets off and arrives, any walk or Tube at either end included
    var departure: Date
    var arrival: Date

    var id: String { trains.map(\.key).joined(separator: "|") }

    var trains: [PlannedLeg] {
        parts.compactMap { if case .train(let leg) = $0 { leg } else { nil } }
    }

    /// The number of times the traveller changes from one train to another
    var changes: Int { max(0, trains.count - 1) }

    /// The transfer onto the train at `index`, or the one that opens the journey for the first train.
    func transfer(before index: Int) -> PlannedTransfer? {
        var seen = 0
        var last: PlannedTransfer?
        for part in parts {
            switch part {
            case .transfer(let transfer):
                last = transfer
            case .train:
                if seen == index { return last }
                seen += 1
                last = nil
            }
        }
        return nil
    }

    /// What is left after the last train, if anything
    var closingTransfer: PlannedTransfer? {
        if case .transfer(let transfer) = parts.last { transfer } else { nil }
    }

    var durationText: String {
        TravelStats.duration(minutes: max(0, Int(arrival.timeIntervalSince(departure) / 60)))
    }

    /// "1 change · Birmingham New Street", or how the journey differs from a direct train
    var summary: String {
        let transfers = parts.compactMap { if case .transfer(let transfer) = $0 { transfer } else { nil } }
        switch changes {
        case 0:
            return transfers.first?.text ?? "Direct"
        case 1:
            // A change between two stations is better described by how it is made
            if let between = transfer(before: 1), between.kind != .change { return "1 change · \(between.text)" }
            return "1 change · \(trains[0].destinationName)"
        default:
            return "\(changes) changes · \(trains.dropLast().map(\.destinationName).joined(separator: ", "))"
        }
    }
}

// MARK: - Client

@MainActor
final class JourneyPlanner {

    static let shared = JourneyPlanner()
    private init() {}

    /// Where Transitous lists the timetable data its routes come from. It asks for this link
    /// to be shown wherever its results are.
    static let sourcesURL = URL(string: "https://transitous.org/sources/")!

    private static let endpoint = "https://api.transitous.org/api/v6/plan"

    /// Says who is asking, as the usage policy requires, with somewhere to reach the author
    private static let userAgent = "Trainy/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (+https://github.com/dylanGadsby1/Trainy)"

    /// A plan is good for a few minutes: going back and forth between screens should not ask again
    private var cache: [String: (fetched: Date, journeys: [PlannedJourney])] = [:]
    private static let cacheLifetime: TimeInterval = 5 * 60

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.httpAdditionalHeaders = ["User-Agent": Self.userAgent, "Accept": "application/json"]
        return URLSession(configuration: configuration)
    }()

    /// Routes from `origin` to `destination` leaving at or after `date` that need a change, a
    /// walk between stations or a ride across town. Direct trains are left to the train feeds.
    func journeys(from origin: UKStation, to destination: UKStation, at date: Date) async throws -> [PlannedJourney] {
        let start = max(date, Date())
        // The planner starts at the station's front door and walks to the platform first, so
        // ask from a little earlier and drop what leaves before the time that was wanted
        let journeys = try await plan(
            from: origin,
            to: destination,
            at: start.addingTimeInterval(-10 * 60),
            notBefore: start.addingTimeInterval(-60),
            includingDirect: false
        )
        return JourneyOptions.current.fewestChanges ? Self.fewestChanges(journeys) : journeys
    }

    /// Ways on to `destination` for a traveller who gets to `station` at `arrival`: what to
    /// take after a change that was missed. Direct trains are included, soonest arrival first.
    func onwardJourneys(from station: UKStation, to destination: UKStation, arrivingAt arrival: Date) async throws -> [PlannedJourney] {
        let start = max(arrival, Date())
        // Asked from the moment of arrival, so the planner's own walk to the platform, or
        // across town, is the time the change is given
        let journeys = try await plan(from: station, to: destination, at: start, notBefore: start, includingDirect: true)
        return journeys.sorted { ($0.arrival, $0.departure) < ($1.arrival, $1.departure) }
    }

    /// Only the routes with the fewest changes of those found.
    nonisolated static func fewestChanges(_ journeys: [PlannedJourney]) -> [PlannedJourney] {
        guard let fewest = journeys.map(\.changes).min() else { return journeys }
        return journeys.filter { $0.changes == fewest }
    }

    private func plan(from origin: UKStation, to destination: UKStation, at time: Date, notBefore earliest: Date, includingDirect: Bool) async throws -> [PlannedJourney] {
        let options = JourneyOptions.current
        let cacheKey = "\(origin.crs)-\(destination.crs)-\(Int(time.timeIntervalSince1970 / 60))-\(includingDirect)-\(options.extraChangeMinutes)-\(options.avoidTube)"
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.fetched) < Self.cacheLifetime {
            return cached.journeys
        }

        var components = URLComponents(string: Self.endpoint)!
        components.queryItems = [
            URLQueryItem(name: "fromPlace", value: "\(origin.lat),\(origin.lon)"),
            URLQueryItem(name: "toPlace", value: "\(destination.lat),\(destination.lon)"),
            URLQueryItem(name: "time", value: ISO8601DateFormatter().string(from: time)),
            // Trains, with the Tube, metros and trams for getting across a city. No coaches or buses.
            URLQueryItem(name: "transitModes", value: options.avoidTube
                ? "HIGHSPEED_RAIL,LONG_DISTANCE,NIGHT_RAIL,REGIONAL_RAIL,SUBURBAN,TRAM"
                : "RAIL,TRAM"),
            // The timetable data carries no official connection times, so never plan a change shorter than this
            URLQueryItem(name: "minTransferTime", value: String(JourneyConnection.minimumMinutes)),
            // On top of that, whatever longer the traveller has said they like to have
            URLQueryItem(name: "additionalTransferTime", value: String(options.extraChangeMinutes)),
            URLQueryItem(name: "numItineraries", value: "6"),
            URLQueryItem(name: "searchWindow", value: "3600"),
            // The app draws its own routes, so spare the server the walking directions
            URLQueryItem(name: "detailedLegs", value: "false")
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let plan = try decoder.decode(Plan.self, from: data)

        let journeys = Self.journeys(in: plan, from: origin, to: destination, notBefore: earliest, includingDirect: includingDirect)
        cache[cacheKey] = (Date(), journeys)
        return journeys
    }

    /// What to tell the user when the planner cannot be reached.
    static func message(for error: Error) -> String {
        print("❌ Journey planning failed: \(error)")
        if let error = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(error.code) {
            return "You seem to be offline. Check your connection and try again."
        }
        return "Routes with a change aren't available right now. Please try again."
    }

    // MARK: - Reading a Plan

    /// The plan's itineraries as journeys, without direct trains or the same trains twice.
    nonisolated static func journeys(in plan: Plan, from origin: UKStation, to destination: UKStation, notBefore earliest: Date, includingDirect: Bool = false) -> [PlannedJourney] {
        var best: [String: PlannedJourney] = [:]

        for itinerary in plan.itineraries {
            guard let journey = journey(from: itinerary, origin: origin, destination: destination, includingDirect: includingDirect),
                  let first = journey.trains.first, first.scheduledDeparture >= earliest else { continue }

            // The same trains can be reached more than one way across town: keep the simplest
            if let known = best[journey.id], known.parts.count <= journey.parts.count { continue }
            best[journey.id] = journey
        }

        return best.values.sorted { ($0.departure, $0.arrival) < ($1.departure, $1.arrival) }
    }

    private nonisolated static func journey(from itinerary: Plan.Itinerary, origin: UKStation, destination: UKStation, includingDirect: Bool) -> PlannedJourney? {
        var parts: [PlannedJourney.Part] = []
        /// Everything since the last train that is not itself a train to follow
        var between: [Plan.Leg] = []
        var lastTrain: PlannedLeg?
        var departure: Date?

        for leg in itinerary.legs {
            // A cancelled train is no way to get anywhere
            if leg.cancelled == true { return nil }

            guard let train = PlannedLeg(leg) else {
                between.append(leg)
                continue
            }

            if let lastTrain {
                parts.append(.transfer(transfer(over: between, from: lastTrain.destinationCRS, to: train.originCRS)))
            } else if let opening = opening(over: between, origin: origin, first: train) {
                parts.append(.transfer(opening))
                departure = between.first?.startTime
            }
            parts.append(.train(train))
            if departure == nil { departure = train.scheduledDeparture }
            lastTrain = train
            between = []
        }

        guard let lastTrain, let departure else { return nil }

        var arrival = lastTrain.scheduledArrival
        if let closing = closing(over: between, destination: destination, last: lastTrain) {
            parts.append(.transfer(closing))
            arrival = between.last?.endTime ?? arrival
        }

        let journey = PlannedJourney(
            title: "\(origin.name) to \(destination.name)",
            parts: parts,
            departure: departure,
            arrival: arrival
        )

        // One train with nothing either side of it is a direct train, which the feeds already list
        return !includingDirect && journey.trains.count == 1 && parts.count == 1 ? nil : journey
    }

    /// The change between two trains.
    private nonisolated static func transfer(over legs: [Plan.Leg], from: String, to: String) -> PlannedTransfer {
        let minutes = max(JourneyConnection.minimumMinutes, legs.reduce(0) { $0 + $1.duration } / 60)

        if let ride = rideText(legs) {
            return PlannedTransfer(kind: .ride, text: ride, minutes: minutes, tubeLines: tubeLines(legs))
        }
        if from != to {
            return PlannedTransfer(kind: .walk, text: "Walk from \(UKStation.name(for: from)) to \(UKStation.name(for: to))", minutes: minutes)
        }
        return PlannedTransfer(kind: .change, text: "Change at \(UKStation.name(for: to))", minutes: minutes)
    }

    /// What comes before the first train, when it is more than walking into the station that was searched for.
    private nonisolated static func opening(over legs: [Plan.Leg], origin: UKStation, first: PlannedLeg) -> PlannedTransfer? {
        let minutes = legs.reduce(0) { $0 + $1.duration } / 60
        if let ride = rideText(legs) {
            return PlannedTransfer(kind: .ride, text: ride, minutes: minutes, tubeLines: tubeLines(legs))
        }
        guard first.originCRS != origin.crs else { return nil }
        return PlannedTransfer(kind: .walk, text: "Walk to \(first.originName)", minutes: minutes)
    }

    /// What comes after the last train, when it does not end at the station that was searched for.
    private nonisolated static func closing(over legs: [Plan.Leg], destination: UKStation, last: PlannedLeg) -> PlannedTransfer? {
        let minutes = legs.reduce(0) { $0 + $1.duration } / 60
        if let ride = rideText(legs) {
            return PlannedTransfer(kind: .ride, text: ride, minutes: minutes)
        }
        guard last.destinationCRS != destination.crs else { return nil }
        return PlannedTransfer(kind: .walk, text: "Walk to \(destination.name)", minutes: minutes)
    }

    /// The Underground lines among `legs`, by the names Transport for London gives them.
    private nonisolated static func tubeLines(_ legs: [Plan.Leg]) -> [String] {
        legs
            .filter { $0.mode == "SUBWAY" && $0.agencyName?.localizedCaseInsensitiveContains("Underground") == true }
            .compactMap(\.displayName)
            .filter { !$0.isEmpty }
    }

    /// "Victoria line from Warren Street to Victoria", "Tube from Euston to Victoria". Nil when
    /// the legs are all on foot.
    private nonisolated static func rideText(_ legs: [Plan.Leg]) -> String? {
        let rides = legs.filter { $0.mode != "WALK" }
        guard let first = rides.first, let last = rides.last else { return nil }

        let isTube = rides.allSatisfy { $0.agencyName?.localizedCaseInsensitiveContains("Underground") == true }
        var vehicle: String
        switch first.mode {
        case "SUBWAY": vehicle = isTube ? "Tube" : "Metro"
        case "TRAM": vehicle = "Tram"
        default: vehicle = "Train"
        }
        // One Tube line is worth naming; a run of them is just "the Tube"
        if rides.count == 1, isTube, let line = first.displayName, !line.isEmpty {
            vehicle = "\(line) line"
        }
        return "\(vehicle) from \(first.from.name) to \(last.to.name)"
    }
}

// MARK: - Response

/// The parts of a Transitous plan the app reads. The field names are the planner's.
struct Plan: Decodable {
    var itineraries: [Itinerary]

    struct Itinerary: Decodable {
        var legs: [Leg]
    }

    struct Leg: Decodable {
        /// "WALK", "SUBWAY", "LONG_DISTANCE", "REGIONAL_RAIL" and so on
        var mode: String
        var from: Place
        var to: Place
        /// Seconds
        var duration: Int
        var startTime: Date
        var endTime: Date
        var scheduledStartTime: Date?
        var scheduledEndTime: Date?
        var agencyName: String?
        /// The operator's two-letter code after an equals sign, "=XC", for National Rail trains
        var agencyId: String?
        var displayName: String?
        var cancelled: Bool?
        var intermediateStops: [Place]?
        var tripFrom: Place?
        var tripTo: Place?
    }

    struct Place: Decodable {
        var name: String
        /// The station's three-letter code, on National Rail stops
        var stopCode: String?
        var lat: Double
        var lon: Double
        var arrival: Date?
        var departure: Date?
        var scheduledArrival: Date?
        var scheduledDeparture: Date?
        /// The platform, as it stands now and as timetabled
        var track: String?
        var scheduledTrack: String?
        var cancelled: Bool?

        /// The station as the app knows it. The planner's code is used when the app has it;
        /// otherwise the nearest station counts, for the few places the two lists disagree on
        /// (St Pancras's Thameslink platforms have a code of their own).
        var crs: String? {
            guard let stopCode else { return nil }
            if knownStationCoordinates[stopCode] != nil { return stopCode }

            let here = CLLocation(latitude: lat, longitude: lon)
            let nearest = ukStations
                .map { (station: $0, metres: here.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lon))) }
                .min { $0.metres < $1.metres }
            return nearest.flatMap { $0.metres < 300 ? $0.station.crs : nil }
        }
    }
}

extension PlannedLeg {
    /// The planner's modes for trains that call at National Rail stations
    private static let trainModes: Set<String> = [
        "RAIL", "HIGHSPEED_RAIL", "LONG_DISTANCE", "NIGHT_RAIL", "REGIONAL_RAIL", "REGIONAL_FAST_RAIL", "SUBURBAN", "METRO"
    ]

    /// Nil for a leg the train feeds cannot follow: a walk, the Tube, a tram, or a train
    /// between places that are not National Rail stations.
    init?(_ leg: Plan.Leg) {
        guard Self.trainModes.contains(leg.mode),
              let origin = leg.from.crs, let destination = leg.to.crs, origin != destination else { return nil }

        let scheduledDeparture = leg.scheduledStartTime ?? leg.startTime
        let scheduledArrival = leg.scheduledEndTime ?? leg.endTime

        var stops = [Stop(crs: origin, name: UKStation.name(for: origin), scheduled: scheduledDeparture, expected: leg.startTime, isCancelled: false)]
        for place in leg.intermediateStops ?? [] {
            guard let crs = place.crs, let time = place.scheduledDeparture ?? place.scheduledArrival else { continue }
            stops.append(Stop(
                crs: crs,
                name: place.name,
                scheduled: time,
                expected: place.departure ?? place.arrival ?? time,
                isCancelled: place.cancelled == true
            ))
        }
        stops.append(Stop(crs: destination, name: UKStation.name(for: destination), scheduled: scheduledArrival, expected: leg.endTime, isCancelled: false))

        self.init(
            originCRS: origin,
            destinationCRS: destination,
            trainOriginName: leg.tripFrom?.name ?? leg.from.name,
            trainDestinationName: leg.tripTo?.name ?? leg.to.name,
            scheduledDeparture: scheduledDeparture,
            expectedDeparture: leg.startTime,
            scheduledArrival: scheduledArrival,
            expectedArrival: leg.endTime,
            operatorCode: leg.agencyId.flatMap { $0.hasPrefix("=") ? String($0.dropFirst()) : nil },
            operatorName: leg.agencyName,
            platform: leg.from.track ?? leg.from.scheduledTrack,
            arrivalPlatform: leg.to.track ?? leg.to.scheduledTrack,
            stops: stops
        )
    }
}

// MARK: - Planned Trains

extension Date {
    private static let ukClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = SavedRoute.ukCalendar
        formatter.timeZone = SavedRoute.ukCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// "HH:mm" in UK time, which is what every train time in the app is
    var ukClock: String { Self.ukClockFormatter.string(from: self) }
}

extension DarwinServiceAdapter {
    /// A train taken from a journey plan, before either train feed has confirmed it. It
    /// carries the timetable only; TrainSync finds it in the feeds by its times, as it does
    /// for any train saved from the timetable.
    init(planned leg: PlannedLeg) {
        let day = SavedRoute.day(of: leg.scheduledDeparture)
        let departure = leg.scheduledDeparture.ukClock

        let identity = "plan:\(day)-\(departure)-\(leg.originCRS)-\(leg.destinationCRS)"
        self.id = identity
        self.serviceID = identity
        self.dataSource = .rtt
        self.isAwaitingLiveData = true

        self.userSearchOriginCRS = leg.originCRS
        self.userSearchDestinationCRS = leg.destinationCRS
        self.originCRS = leg.originCRS
        self.originName = leg.trainOriginName
        self.destinationCRS = leg.destinationCRS
        self.destinationName = leg.trainDestinationName

        self.scheduledDeparture = departure
        self.realtimeDeparture = leg.expectedDeparture.ukClock
        self.userSearchDestinationScheduledArrivalTime = leg.scheduledArrival.ukClock
        self.userSearchDestinationArrivalTime = leg.expectedArrival.ukClock
        self.scheduleMetadata = ScheduleMetadata(identity: nil, departureDate: day)

        self.platform = leg.platform ?? "TBC"
        self.atocCode = leg.operatorCode
        self.atocName = leg.operatorName
        self.isCancelledService = false
        self.delayMinutes = 0

        self.stops = leg.stops.map {
            Stop(
                crs: $0.crs,
                name: $0.name,
                scheduled: $0.scheduled.ukClock,
                expected: $0.expected.ukClock,
                hasCalled: false,
                isCancelled: $0.isCancelled
            )
        }
        self.delayMinutes = max(departureDelayMinutes, arrivalDelayMinutes)
    }
}

// MARK: - Search Options

/// How the traveller likes journeys with a change to be planned. Kept between launches, and
/// used wherever a journey is planned: search, a missed connection and a commute.
struct JourneyOptions: Equatable {
    static let extraChangeMinutesKey = "journey.extraChangeMinutes"
    static let fewestChangesKey = "journey.fewestChanges"
    static let avoidTubeKey = "journey.avoidTube"

    /// Minutes wanted at every change on top of the least a change is planned with
    var extraChangeMinutes = 0
    /// Show only the routes with the fewest changes
    var fewestChanges = false
    /// Plan without the Underground and other metros
    var avoidTube = false

    static var current: JourneyOptions {
        let defaults = UserDefaults.standard
        return JourneyOptions(
            extraChangeMinutes: defaults.integer(forKey: extraChangeMinutesKey),
            fewestChanges: defaults.bool(forKey: fewestChangesKey),
            avoidTube: defaults.bool(forKey: avoidTubeKey)
        )
    }
}

// MARK: - Tube Status

/// How the Underground lines are running, from Transport for London's open feed. Shown on a
/// change that crosses London by Tube.
@MainActor
final class TubeStatus {

    static let shared = TubeStatus()
    private init() {}

    struct Line: Equatable {
        /// "Victoria"
        var name: String
        /// "Good Service", "Minor Delays", "Part Closure"
        var status: String
        var isGood: Bool
    }

    private static let endpoint = URL(string: "https://api.tfl.gov.uk/Line/Mode/tube/Status")!
    private static let lifetime: TimeInterval = 3 * 60

    private var cached: (fetched: Date, lines: [Line])?

    /// How each of `names` is running now. Empty when the feed cannot be read: the change is
    /// then shown without it.
    func lines(named names: [String]) async -> [Line] {
        guard !names.isEmpty else { return [] }
        let all = await allLines()
        return names.compactMap { name in
            all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
    }

    private func allLines() async -> [Line] {
        if let cached, Date().timeIntervalSince(cached.fetched) < Self.lifetime { return cached.lines }

        guard let (data, response) = try? await URLSession.shared.data(from: Self.endpoint),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let feed = try? JSONDecoder().decode([Feed].self, from: data) else { return cached?.lines ?? [] }

        let lines = feed.map { line in
            // The worst of a line's statuses is the one that matters to someone about to use it
            let worst = line.lineStatuses.min { $0.statusSeverity < $1.statusSeverity }
            return Line(
                name: line.name,
                status: worst?.statusSeverityDescription ?? "Good Service",
                isGood: (worst?.statusSeverity ?? 10) >= 10
            )
        }
        cached = (Date(), lines)
        return lines
    }

    /// The parts of the feed the app reads. The field names are Transport for London's.
    private struct Feed: Decodable {
        var name: String
        var lineStatuses: [Status]

        struct Status: Decodable {
            /// 10 is a good service; lower is worse
            var statusSeverity: Int
            var statusSeverityDescription: String
        }
    }
}

// MARK: - Following a Planned Journey

extension PlannedJourney {
    /// Adds the journey's trains to My Trains, tied together as one journey. Each train is
    /// looked up in the train feeds first, so it is live straight away when it can be; one
    /// that cannot be found yet is saved from the plan and found by the next sync.
    @MainActor
    func follow(in context: ModelContext) async {
        await save(in: context, journeyID: UUID().uuidString, title: title, firstIndex: 0, plannedArrival: trains.last?.scheduledArrival, disruptedBy: nil)
    }

    /// Takes over the rest of a journey being followed, from its train at position `index`
    /// on: the way to carry on after a change that was missed, or a train that was cancelled.
    /// - Parameter operatorCode: The operator whose late or cancelled train made this necessary.
    @MainActor
    func replace(_ journey: SavedJourney, from index: Int, causedBy operatorCode: String?, in context: ModelContext) async {
        guard journey.legs.indices.contains(index) else { return }

        // How late the traveller ends up is still measured against the journey as first
        // planned, and put down to whichever train went wrong first
        let plannedArrival = journey.plannedArrival
        let disruptedBy = journey.disruptedBy ?? operatorCode
        let firstIndex = index > 0 ? journey.legs[index - 1].legIndex + 1 : journey.legs[index].legIndex

        for leg in journey.legs[..<index] {
            leg.journeyPlannedArrival = plannedArrival
            leg.journeyDisruptedBy = disruptedBy
        }
        // The trains given up go altogether, a cancelled one included: what it cost the
        // traveller is the journey's lateness, which the journey's own claim covers
        for leg in journey.legs[index...] where !leg.isPast {
            if let service = leg.service {
                LiveActivityManager.shared.endTracking(for: service)
            }
            context.delete(leg)
        }

        await save(in: context, journeyID: journey.id, title: journey.title, firstIndex: firstIndex, plannedArrival: plannedArrival, disruptedBy: disruptedBy)
    }

    @MainActor
    private func save(in context: ModelContext, journeyID: String, title: String, firstIndex: Int, plannedArrival: Date?, disruptedBy: String?) async {
        let legs = trains
        var trains = legs.map(DarwinServiceAdapter.init(planned:))

        for index in trains.indices {
            guard var found = await TrainSync.shared.refreshed(trains[index]) else { continue }
            // A train only Realtime Trains knows goes by its identity there, like one found by searching
            if found.dataSource == .rtt, let identity = found.rttIdentity {
                found.id = identity
                found.serviceID = identity
            }
            trains[index] = found
        }

        let saved = (try? context.fetch(FetchDescriptor<SavedTrain>(predicate: #Predicate { !$0.isPast }))) ?? []

        for (index, train) in trains.enumerated() {
            // A train already being followed joins the journey rather than appearing twice
            let record: SavedTrain
            if let existing = saved.first(where: { !$0.isDeleted && $0.service?.isSameJourney(as: train) == true }) {
                record = existing
            } else if let data = try? JSONEncoder().encode(train) {
                record = SavedTrain(id: train.id, serviceData: data)
                context.insert(record)
            } else {
                continue
            }

            let transfer = transfer(before: index)
            record.journeyID = journeyID
            record.legIndex = firstIndex + index
            record.journeyTitle = title
            // A plain change of platform is described by the stations either side of it
            record.transferNote = transfer.flatMap { $0.kind == .change ? nil : $0.text }
            record.transferMinutes = transfer?.minutes
            record.transferLines = transfer.flatMap { $0.tubeLines.isEmpty ? nil : $0.tubeLines.joined(separator: ",") }
            record.onwardNote = index == trains.count - 1 ? closingTransfer?.text : nil
            record.arrivalPlatform = legs[index].arrivalPlatform
            record.journeyPlannedArrival = plannedArrival
            record.journeyDisruptedBy = disruptedBy
        }

        try? context.save()
    }
}
