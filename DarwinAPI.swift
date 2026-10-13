import Foundation
import SwiftUI

// MARK: - All Darwin-related types consolidated in one file
// This file contains: DarwinService (API), DarwinModels, and DarwinServiceAdapter

// ============================================================================
// MARK: - Darwin API Service
// ============================================================================

final class DarwinService {

    static let shared = DarwinService()
    private init() {}

    // ── Credentials ──────────────────────────────────────────────────────────
    // Your National Rail Data Portal API key
    private let apiKey = Secrets.railDataKey

    // Rail Data Marketplace "Live Departure Board" product.
    // This product only serves GetDepartureBoard and GetDepBoardWithDetails.
    // Arrivals, service details and next/fastest departures are separate
    // subscriptions with their own base URLs and keys.
    private let baseURL = "https://api1.raildata.org.uk/1010-live-departure-board-dep1_2/LDBWS/api/20220120"

    /// Darwin only accepts a time offset of up to two hours either side of now.
    static let maxOffsetMinutes = 119

    /// How far ahead Darwin lists a train: a board can start 119 minutes from now
    /// and then covers the two hours after that, so about four hours in all.
    static let maxReachMinutes = maxOffsetMinutes + 119

    // MARK: - URL Session

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    // MARK: - Generic Fetch

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // With a Trainy server the board comes through it, and the key stays there
        if let relayed = TrainyServer.request("darwin/\(url.pathComponents.suffix(2).joined(separator: "/"))",
                                              query: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []) {
            request = relayed
        }

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw DarwinError.invalidResponse
        }

        if http.statusCode == 429 {
            throw DarwinError.rateLimitExceeded
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw DarwinError.invalidAccessToken
        }

        guard http.statusCode == 200 else {
            print("❌ Darwin API Error: \(http.statusCode) for URL: \(url)")
            throw DarwinError.httpError(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("❌ Darwin decoding error for URL \(url): \(error)")
            throw error
        }
    }

    // MARK: - Public API

    /// Get live departure board for a station
    /// - Parameters:
    ///   - crs: Station CRS code (e.g. "EUS" for London Euston)
    ///   - numRows: Number of services to return (default 10)
    ///   - filterCrs: Optional destination filter CRS code
    ///   - filterType: "to" or "from" (default "to")
    ///   - timeOffset: Minutes from now at which the board starts (-119...119)
    ///   - timeWindow: Minutes after the offset to cover (default 120)
    ///   - withDetails: Include each service's calling points
    func departures(
        from crs: String,
        numRows: Int = 10,
        filterCrs: String? = nil,
        filterType: String = "to",
        timeOffset: Int = 0,
        timeWindow: Int = 120,
        withDetails: Bool = false
    ) async throws -> DarwinDepartureBoard {
        let endpoint = withDetails ? "GetDepBoardWithDetails" : "GetDepartureBoard"
        var components = URLComponents(string: "\(baseURL)/\(endpoint)/\(crs.uppercased())")!

        var queryItems = [
            URLQueryItem(name: "numRows", value: String(numRows))
        ]

        if let filterCrs = filterCrs {
            queryItems.append(URLQueryItem(name: "filterCrs", value: filterCrs.uppercased()))
            queryItems.append(URLQueryItem(name: "filterType", value: filterType))
        }

        if timeOffset != 0 {
            queryItems.append(URLQueryItem(name: "timeOffset", value: String(timeOffset)))
        }

        if timeWindow != 120 {
            queryItems.append(URLQueryItem(name: "timeWindow", value: String(timeWindow)))
        }

        components.queryItems = queryItems

        guard let url = components.url else { throw DarwinError.invalidResponse }
        return try await fetch(url)
    }

    /// Live trains between two stations from `date` onwards, with arrival times.
    /// Covers everything Darwin lists: one board starting at `date`, plus a second
    /// starting at the furthest offset when the first stops short of the four-hour reach.
    /// Returns nothing for a `date` beyond that reach.
    func search(from origin: String, to destination: String, at date: Date) async throws -> [DarwinServiceAdapter] {
        let now = Date()
        let minutesAhead = max(0, Int(date.timeIntervalSince(now) / 60))
        guard minutesAhead <= Self.maxReachMinutes else { return [] }

        let offsets = minutesAhead < Self.maxOffsetMinutes
            ? [minutesAhead, Self.maxOffsetMinutes]
            : [Self.maxOffsetMinutes]

        var trains: [DarwinServiceAdapter] = []
        for (index, offset) in offsets.enumerated() {
            do {
                let board = try await departures(
                    from: origin,
                    numRows: 150,
                    filterCrs: destination,
                    filterType: "to",
                    timeOffset: offset,
                    withDetails: true
                )
                let boardStart = now.addingTimeInterval(TimeInterval(offset * 60))
                // The two boards overlap, so skip trains the first one already gave
                for train in board.toAdapters(origin: origin, destination: destination, date: boardStart)
                where !trains.contains(where: { $0.id == train.id }) {
                    trains.append(train)
                }
            } catch where index > 0 {
                // The first board already holds the next two hours, so the extension is optional
            }
        }

        // A board at the furthest offset can start before the time that was asked for
        return trains.filter { ($0.scheduledDepartureDate ?? date) >= date.addingTimeInterval(-60) }
    }

    /// Re-reads the origin departure board and returns `train` with its live times applied.
    /// A train that was found through Realtime Trains is matched by its journey and takes on
    /// its Darwin identity here. Returns nil when the service is not listed: Darwin lists a
    /// train from about four hours before it leaves the origin until two hours after.
    func refreshed(_ train: DarwinServiceAdapter, now: Date = Date()) async -> DarwinServiceAdapter? {
        guard let departure = train.scheduledDepartureDate else { return nil }

        let minutesUntilDeparture = Int(departure.timeIntervalSince(now) / 60)
        guard (-180...Self.maxReachMinutes).contains(minutesUntilDeparture) else { return nil }

        // Start the window half an hour early so a retimed service is still inside it.
        let offset = min(max(minutesUntilDeparture - 30, -Self.maxOffsetMinutes), Self.maxOffsetMinutes)

        guard let board = try? await departures(
            from: train.userSearchOriginCRS ?? train.originCRS,
            numRows: 150,
            filterCrs: train.userSearchDestinationCRS ?? train.destinationCRS,
            filterType: "to",
            timeOffset: offset,
            withDetails: true
        ), let services = board.trainServices,
           let service = services.first(where: { $0.id == train.id })
            ?? services.first(where: { train.isSameTrain(as: $0) }) else {
            return nil
        }

        var updated = train
        updated.adoptDarwinIdentity(of: service)
        return updated
    }
}

// ============================================================================
// MARK: - Darwin Errors
// ============================================================================

enum DarwinError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case rateLimitExceeded
    case invalidAccessToken

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response."
        case .httpError(let code):
            return "Server returned HTTP \(code)."
        case .rateLimitExceeded:
            return "Too many requests. Please wait a moment and try again."
        case .invalidAccessToken:
            return "Invalid Darwin access token. Check your credentials."
        }
    }
}

// ============================================================================
// MARK: - Darwin Models
// ============================================================================
// Only fields the app reads are declared. A declared field with the wrong type
// fails the whole board, so unused fields are left for the decoder to ignore.

/// Main departure board response
struct DarwinDepartureBoard: Codable {
    let generatedAt: String?
    let locationName: String?
    let crs: String?
    let filterLocationName: String?
    let filtercrs: String?
    let platformAvailable: Bool?
    let areServicesAvailable: Bool?
    let trainServices: [DarwinServiceModel]?
    let busServices: [DarwinServiceModel]?
    let ferryServices: [DarwinServiceModel]?
}

/// Individual train service
struct DarwinServiceModel: Codable, Identifiable {
    let serviceID: String?
    let sta: String?  // Scheduled time of arrival
    let eta: String?  // Estimated time of arrival
    let std: String?  // Scheduled time of departure
    let etd: String?  // Estimated time of departure
    let platform: String?
    let `operator`: String?
    let operatorCode: String?
    let isCircularRoute: Bool?
    let isCancelled: Bool?
    /// The service still runs but no longer calls at the station the board was filtered by
    let filterLocationCancelled: Bool?
    let serviceType: String?  // "train", "bus" or "ferry"
    let length: Int?
    let cancelReason: String?
    let delayReason: String?
    let origin: [DarwinLocation]?
    let destination: [DarwinLocation]?
    /// Only present on boards requested with details
    let subsequentCallingPoints: [DarwinCallingPointGroup]?

    var id: String {
        serviceID ?? "\(std ?? "")-\(destinationName)"
    }

    /// Computed status
    var status: DarwinServiceStatus {
        if isCancelled == true {
            return .cancelled
        }

        // Check if delayed
        if let etd = etd, let std = std, etd != std, etd != "On time" {
            return .delayed
        }

        if let eta = eta, let sta = sta, eta != sta, eta != "On time" {
            return .delayed
        }

        return .onTime
    }

    /// Human-readable destination name
    var destinationName: String {
        destination?.first?.locationName ?? "Unknown"
    }

    /// Human-readable origin name
    var originName: String {
        origin?.first?.locationName ?? "Unknown"
    }

    /// The first later stop at a station. Needs a board requested with details.
    func stop(at crs: String?) -> DarwinCallingPoint? {
        subsequentCallingPoints?.flatMap { $0.callingPoint ?? [] }.first { $0.crs == crs }
    }
}

/// Service location (origin/destination)
struct DarwinLocation: Codable {
    let locationName: String?
    let crs: String?
    let via: String?
}

/// One portion of a service's onward route (a train that divides has several)
struct DarwinCallingPointGroup: Codable {
    let callingPoint: [DarwinCallingPoint]?
}

/// Calling point (station stop)
struct DarwinCallingPoint: Codable, Identifiable {
    let locationName: String?
    let crs: String?
    let st: String?   // Scheduled time
    let et: String?   // Estimated time
    let at: String?   // Actual time
    let isCancelled: Bool?

    var id: String {
        (crs ?? "") + (st ?? "")
    }
}

/// Service status enum
enum DarwinServiceStatus {
    case onTime
    case delayed
    case cancelled

    var displayText: String {
        switch self {
        case .onTime: return "ON TIME"
        case .delayed: return "DELAYED"
        case .cancelled: return "CANCELLED"
        }
    }

    var color: String {
        switch self {
        case .onTime: return "green"
        case .delayed: return "orange"
        case .cancelled: return "red"
        }
    }
}

// ============================================================================
// MARK: - Darwin Time Values
// ============================================================================

/// Darwin reports estimated and actual times either as "HH:mm" or as a status
/// word: "On time", "Delayed", "Cancelled" or "No report".
enum DarwinTime {

    /// "HH:mm" if `value` is a clock time, otherwise nil.
    static func clock(_ value: String?) -> String? {
        guard let value = value else { return nil }
        let text = value.filter { $0.isNumber || $0 == ":" }
        let parts = text.split(separator: ":")
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              hour < 24, minute < 60 else { return nil }
        return text
    }

    /// Minutes since midnight for a "HH:mm" clock time.
    static func minutes(_ value: String?) -> Int? {
        guard let text = clock(value) else { return nil }
        return (Int(text.prefix(2)) ?? 0) * 60 + (Int(text.suffix(2)) ?? 0)
    }

    /// The time a train is expected: the estimate when Darwin gives one, otherwise the schedule.
    static func expected(scheduled: String?, estimate: String?) -> String? {
        clock(estimate) ?? clock(scheduled)
    }

    /// True when Darwin reports a delay but has no new time yet.
    static func isDelayedWithoutEstimate(_ estimate: String?) -> Bool {
        estimate?.lowercased() == "delayed"
    }

    /// Minutes late, never negative. Handles a delay that runs past midnight.
    static func delay(scheduled: String?, expected: String?) -> Int {
        guard let scheduled = minutes(scheduled), let expected = minutes(expected) else { return 0 }
        let late = (expected - scheduled + 1440) % 1440
        return late > 720 ? 0 : late
    }
}

// ============================================================================
// MARK: - Darwin Service Adapter (the app's train model)
// ============================================================================

/// Which feed a train's `id` belongs to.
enum TrainDataSource: String, Codable {
    case darwin
    case rtt
}

/// A train on one user journey (origin → destination), from Darwin or Realtime Trains.
/// This is what MyTrainCard, SavedTrain and the Live Activity work with.
struct DarwinServiceAdapter: Codable, Identifiable, Equatable {
    var id: String

    // Core identification
    var serviceID: String
    var userSearchOriginCRS: String?
    var userSearchDestinationCRS: String?

    // Origin/Destination
    var originCRS: String
    var originName: String
    var destinationCRS: String
    var destinationName: String

    // Timing ("HH:mm"; the realtime/arrival values are the expected times)
    var scheduledDeparture: String
    var realtimeDeparture: String
    var userSearchDestinationArrivalTime: String?
    var userSearchDestinationScheduledArrivalTime: String?

    // Service info
    var platform: String
    var atocName: String?
    var atocCode: String?
    /// Minutes late: at the destination once the train has arrived, and until then
    /// the larger of the departure delay and the expected arrival delay
    var delayMinutes: Int
    var isCancelledService: Bool
    /// Darwin reports the train as delayed but has no new time yet
    var hasUnknownDelay: Bool?

    // Feed tracking
    /// The feed `id` belongs to. A train found through Realtime Trains switches to `.darwin`
    /// once Darwin lists it. Nil on trains saved before this was recorded, which are Darwin's.
    var dataSource: TrainDataSource?
    /// The Realtime Trains identity ("gb-nr:Y80917:2026-10-12"), kept after the switch to
    /// Darwin so the train can still be followed once Darwin drops it
    var rttIdentity: String?
    /// Only the timetable is known so far: no feed has reported on this train yet
    var isAwaitingLiveData: Bool?
    /// The train has been reported at the user's destination
    var hasArrived: Bool?
    /// The stations the train calls at on the user's journey, origin and destination included.
    /// Nil until a feed has listed them, and on trains saved before they were recorded.
    var stops: [Stop]?
    /// Darwin's own sentence for the delay ("This train has been delayed by a signalling fault")
    var delayReason: String?
    /// Darwin's own sentence for the cancellation
    var cancelReason: String?
    /// How many coaches the train has, when Darwin knows
    var coaches: Int?

    struct Stop: Codable, Equatable, Identifiable {
        var crs: String
        var name: String
        /// "HH:mm": when the train is due to leave, or to arrive at the last stop
        var scheduled: String
        /// The expected time, or the actual one once the train has been through
        var expected: String
        /// The train has been reported at this stop
        var hasCalled: Bool
        var isCancelled: Bool

        var id: String { crs + scheduled }

        var delayMinutes: Int {
            DarwinTime.delay(scheduled: scheduled, expected: expected)
        }
    }

    // Schedule metadata (for compatibility)
    var scheduleMetadata: ScheduleMetadata?

    struct ScheduleMetadata: Codable, Equatable {
        var identity: String?
        /// The day the train is scheduled to depart, "yyyy-MM-dd"
        var departureDate: String?
    }

    // MARK: - Computed Properties

    /// Train status computed from cancellation and delay info
    var trainStatus: TrainStatus {
        if isCancelledService {
            return .cancelled
        } else if delayMinutes > 0 || hasUnknownDelay == true {
            return .delayed
        } else if isAwaitingLiveData == true {
            return .scheduled
        } else {
            return .onTime
        }
    }

    var departureDelayMinutes: Int {
        DarwinTime.delay(scheduled: scheduledDeparture, expected: realtimeDeparture)
    }

    var arrivalDelayMinutes: Int {
        DarwinTime.delay(scheduled: userSearchDestinationScheduledArrivalTime, expected: userSearchDestinationArrivalTime)
    }

    /// Why the train is late or cancelled, in Darwin's words. Nil while it is on time.
    var disruptionReason: String? {
        if isCancelledService { return cancelReason ?? delayReason }
        return delayMinutes > 0 || hasUnknownDelay == true ? delayReason : nil
    }

    // MARK: - Initializers

    /// - Parameter date: The time the board was requested for, used to work out which day the train runs.
    init(from darwinService: DarwinServiceModel, origin: String, destination: String, date: Date) {
        self.id = darwinService.id
        self.serviceID = darwinService.id

        self.userSearchOriginCRS = origin
        self.userSearchDestinationCRS = destination

        // Origin/Destination
        self.originCRS = origin
        self.originName = darwinService.originName
        self.destinationCRS = destination
        self.destinationName = darwinService.destinationName

        // Operator
        self.atocName = darwinService.operator
        self.atocCode = darwinService.operatorCode

        // Schedule
        let scheduled = DarwinTime.clock(darwinService.std) ?? "--:--"
        self.scheduledDeparture = scheduled
        self.scheduleMetadata = ScheduleMetadata(
            identity: darwinService.id,
            departureDate: Self.runDate(forDeparture: scheduled, near: date)
        )

        // Live fields, filled in by apply(_:)
        self.realtimeDeparture = scheduled
        self.platform = "TBC"
        self.delayMinutes = 0
        self.isCancelledService = false

        apply(darwinService)
    }

    /// Converts a train saved before the Darwin migration.
    init(legacy rtt: RTTServiceModel) {
        self.id = rtt.id
        self.serviceID = rtt.id
        self.userSearchOriginCRS = rtt.userSearchOriginCRS
        self.userSearchDestinationCRS = rtt.userSearchDestinationCRS
        self.originCRS = rtt.originCRS
        self.originName = rtt.originName
        self.destinationCRS = rtt.destinationCRS
        self.destinationName = rtt.destinationName
        self.scheduledDeparture = rtt.scheduledDeparture
        self.realtimeDeparture = rtt.realtimeDeparture
        self.userSearchDestinationArrivalTime = rtt.userSearchDestinationArrivalTime
        self.userSearchDestinationScheduledArrivalTime = rtt.userSearchDestinationScheduledArrivalTime
        self.platform = rtt.platform
        self.atocName = rtt.atocName
        self.atocCode = rtt.atocCode
        self.delayMinutes = rtt.delayMinutes
        self.isCancelledService = rtt.isCancelledService
        self.scheduleMetadata = ScheduleMetadata(
            identity: rtt.scheduleMetadata?.identity,
            departureDate: rtt.scheduleMetadata?.departureDate
        )
    }

    /// A timetabled train found through Realtime Trains, before Darwin lists it.
    /// - Parameters:
    ///   - service: The train as it appears in the origin station's departures.
    ///   - arrival: Its arrival at the user's destination, when known.
    init?(rtt service: RTTServiceModel, arrival: RTTTimeNode?, origin: String, destination: String) {
        guard let identity = service.scheduleMetadata?.uniqueIdentity,
              let departure = service.temporalData?.departure,
              let scheduled = departure.scheduledClock else { return nil }

        self.id = identity
        self.serviceID = identity
        self.rttIdentity = identity
        self.dataSource = .rtt
        self.isAwaitingLiveData = true

        self.userSearchOriginCRS = origin
        self.userSearchDestinationCRS = destination
        self.originCRS = origin
        self.originName = service.originName
        self.destinationCRS = destination
        self.destinationName = service.destinationName

        self.atocName = service.atocName
        self.atocCode = service.atocCode

        // The day comes from the call at the user's station: a sleeper's own departure date can be the day before
        self.scheduledDeparture = scheduled
        self.scheduleMetadata = ScheduleMetadata(identity: identity, departureDate: departure.scheduledDay)

        // Live fields, filled in by applyRTT
        self.realtimeDeparture = scheduled
        self.platform = "TBC"
        self.delayMinutes = 0
        self.isCancelledService = false

        applyRTT(departure: departure, arrival: arrival, platform: service.locationMetadata?.platform)
    }

    // MARK: - Live Updates

    /// Applies the live fields of a board entry: times, platform, cancellation and delay.
    mutating func apply(_ service: DarwinServiceModel) {
        realtimeDeparture = DarwinTime.expected(scheduled: service.std, estimate: service.etd) ?? scheduledDeparture

        // Darwin withdraws the platform once a train has left, so keep the last one seen
        if let platform = service.platform {
            self.platform = platform
        }

        isCancelledService = service.isCancelled == true || service.filterLocationCancelled == true
        hasUnknownDelay = DarwinTime.isDelayedWithoutEstimate(service.etd)

        isAwaitingLiveData = false

        // Darwin drops a train from the board once it has left, so keep the last reasons and length seen
        if let reason = service.delayReason, !reason.isEmpty {
            delayReason = reason
        }
        if let reason = service.cancelReason, !reason.isEmpty {
            cancelReason = reason
        }
        if let length = service.length, length > 0 {
            coaches = length
        }

        // Arrival at the user's destination, from the calling points
        if let stop = service.stop(at: userSearchDestinationCRS) {
            userSearchDestinationScheduledArrivalTime = DarwinTime.clock(stop.st)
            userSearchDestinationArrivalTime = DarwinTime.expected(scheduled: stop.st, estimate: stop.at ?? stop.et)
            hasArrived = stop.at != nil

            if stop.isCancelled == true {
                isCancelledService = true
            }
            if DarwinTime.isDelayedWithoutEstimate(stop.et) {
                hasUnknownDelay = true
            }
        }

        // A board without details has no calling points: keep the ones already known
        if let stops = darwinStops(of: service) {
            self.stops = stops
        }

        updateDelay()
    }

    /// The user's journey along a board entry: the board's own station, then the calling
    /// points as far as the destination.
    private func darwinStops(of service: DarwinServiceModel) -> [Stop]? {
        let origin = userSearchOriginCRS ?? originCRS
        let destination = userSearchDestinationCRS ?? destinationCRS

        // A train that divides has several portions: follow the one that reaches the destination
        guard let portion = service.subsequentCallingPoints?
            .compactMap(\.callingPoint)
            .first(where: { $0.contains { $0.crs == destination } }),
              let last = portion.firstIndex(where: { $0.crs == destination }) else { return nil }

        let first = Stop(
            crs: origin,
            name: ukStations.first { $0.crs == origin }?.name ?? origin,
            scheduled: scheduledDeparture,
            expected: realtimeDeparture,
            // The board has no actual departure time, but a report further on means it has left
            hasCalled: portion.contains { $0.at != nil },
            isCancelled: service.isCancelled == true
        )

        return [first] + portion[...last].compactMap { point in
            guard let crs = point.crs, let scheduled = DarwinTime.clock(point.st) else { return nil }
            return Stop(
                crs: crs,
                name: point.locationName ?? crs,
                scheduled: scheduled,
                expected: DarwinTime.expected(scheduled: point.st, estimate: point.at ?? point.et) ?? scheduled,
                hasCalled: point.at != nil,
                isCancelled: point.isCancelled == true
            )
        }
    }

    /// Applies Realtime Trains' times for the user's origin and destination calls.
    mutating func applyRTT(departure: RTTTimeNode?, arrival: RTTTimeNode?, platform: RTTPlatformNode?) {
        if let departure = departure {
            realtimeDeparture = departure.expectedClock ?? scheduledDeparture
        }

        if let platform = platform?.actual ?? platform?.forecast ?? platform?.planned {
            self.platform = platform
        }

        isCancelledService = departure?.isCancelled == true || arrival?.isCancelled == true
        hasUnknownDelay = false

        if let arrival = arrival {
            userSearchDestinationScheduledArrivalTime = arrival.scheduledClock ?? userSearchDestinationScheduledArrivalTime
            userSearchDestinationArrivalTime = arrival.expectedClock ?? userSearchDestinationArrivalTime
            hasArrived = arrival.realtimeActual != nil
        }

        // An actual time means the train is being reported on, not just timetabled
        if departure?.realtimeActual != nil || arrival?.realtimeActual != nil {
            isAwaitingLiveData = false
        }

        updateDelay()
    }

    private mutating func updateDelay() {
        delayMinutes = hasArrived == true ? arrivalDelayMinutes : max(departureDelayMinutes, arrivalDelayMinutes)
    }

    // MARK: - Matching Across Feeds

    /// Names the journey the same way before and after the train moves from the timetable
    /// to Darwin, which changes its `id`. The server uses the same key.
    var journeyKey: String {
        [
            scheduleMetadata?.departureDate ?? "",
            scheduledDeparture,
            userSearchOriginCRS ?? originCRS,
            userSearchDestinationCRS ?? destinationCRS
        ].joined(separator: "-")
    }

    /// True when `other` is the same train on the same journey, whichever feed each came from.
    /// Darwin and Realtime Trains share no ID, but they agree on the public timetable.
    func isSameJourney(as other: DarwinServiceAdapter) -> Bool {
        guard (userSearchOriginCRS ?? originCRS) == (other.userSearchOriginCRS ?? other.originCRS),
              (userSearchDestinationCRS ?? destinationCRS) == (other.userSearchDestinationCRS ?? other.destinationCRS),
              scheduleMetadata?.departureDate == other.scheduleMetadata?.departureDate,
              scheduledDeparture == other.scheduledDeparture else { return false }

        // Two trains can leave in the same minute, so one more detail has to agree
        if let arrival = userSearchDestinationScheduledArrivalTime,
           arrival == other.userSearchDestinationScheduledArrivalTime {
            return true
        }
        return atocCode == other.atocCode
    }

    /// True when a Darwin board entry for this train's origin is this train.
    func isSameTrain(as service: DarwinServiceModel) -> Bool {
        guard DarwinTime.clock(service.std) == scheduledDeparture else { return false }

        if let arrival = userSearchDestinationScheduledArrivalTime,
           arrival == DarwinTime.clock(service.stop(at: userSearchDestinationCRS)?.st) {
            return true
        }
        return atocCode == service.operatorCode
    }

    /// Takes on the identity and live data of this train's Darwin board entry.
    mutating func adoptDarwinIdentity(of service: DarwinServiceModel) {
        id = service.id
        serviceID = service.id
        scheduleMetadata?.identity = service.id
        dataSource = .darwin
        apply(service)
    }
}

// MARK: - Dates

extension DarwinServiceAdapter {

    /// Darwin's clock times are UK local time, wherever the phone is.
    private static let ukCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .current
        return calendar
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = ukCalendar
        formatter.timeZone = ukCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// The day ("yyyy-MM-dd") on which a departure at `clock` falls closest to `reference`.
    /// A board requested at 23:50 lists 00:10 departures, which run the next day.
    private static func runDate(forDeparture clock: String, near reference: Date) -> String {
        guard let minutes = DarwinTime.minutes(clock) else {
            return dayFormatter.string(from: reference)
        }
        let today = ukCalendar.startOfDay(for: reference)
        let candidates = [-1, 0, 1].compactMap { day in
            ukCalendar.date(byAdding: .day, value: day, to: today)?.addingTimeInterval(TimeInterval(minutes * 60))
        }
        let closest = candidates.min {
            abs($0.timeIntervalSince(reference)) < abs($1.timeIntervalSince(reference))
        }
        return dayFormatter.string(from: closest ?? reference)
    }

    var scheduledDepartureDate: Date? {
        guard let day = scheduleMetadata?.departureDate,
              let midnight = Self.dayFormatter.date(from: day),
              let minutes = DarwinTime.minutes(scheduledDeparture) else { return nil }
        return midnight.addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// The date of a clock time at or after the scheduled departure, rolling past midnight.
    private func date(of clock: String?) -> Date? {
        guard let departure = scheduledDepartureDate,
              let departureMinutes = DarwinTime.minutes(scheduledDeparture),
              let minutes = DarwinTime.minutes(clock) else { return nil }
        var elapsed = minutes - departureMinutes
        if elapsed < -60 { elapsed += 1440 }
        return departure.addingTimeInterval(TimeInterval(elapsed * 60))
    }

    var expectedDepartureDate: Date? {
        date(of: realtimeDeparture)
    }

    var expectedArrivalDate: Date? {
        date(of: userSearchDestinationArrivalTime ?? userSearchDestinationScheduledArrivalTime)
    }

    var scheduledArrivalDate: Date? {
        date(of: userSearchDestinationScheduledArrivalTime ?? userSearchDestinationArrivalTime)
    }

    /// Where the train is thought to be at `now`: the two stops it is between, and how far
    /// from the first to the second. Worked out from the stops' expected times, so it is an
    /// estimate rather than a report. Nil before the train leaves the user's origin, once
    /// it is due at the destination, and when the stops are not known.
    func position(at now: Date = Date()) -> (from: Stop, to: Stop, fraction: Double)? {
        guard !isCancelledService, hasArrived != true else { return nil }

        let timed = (stops ?? [])
            .filter { !$0.isCancelled }
            .compactMap { stop in date(of: stop.expected).map { (stop: stop, due: $0) } }
        guard let next = timed.firstIndex(where: { $0.due > now }), next > 0 else { return nil }

        let from = timed[next - 1], to = timed[next]
        let leg = to.due.timeIntervalSince(from.due)
        let fraction = leg > 0 ? now.timeIntervalSince(from.due) / leg : 0
        return (from.stop, to.stop, min(1, max(0, fraction)))
    }

    /// How many of the stops the train has left behind at `now`, by report or by the clock.
    func stopsPassed(at now: Date = Date()) -> Int {
        guard let stops, !isCancelledService else { return 0 }
        if hasArrived == true { return stops.count }

        let lastPassed = stops.lastIndex { stop in
            stop.hasCalled || (date(of: stop.expected).map { $0 <= now } ?? false)
        }
        return lastPassed.map { $0 + 1 } ?? 0
    }

    /// Fraction of the journey completed at `now`: 0 before departure, 1 after arrival.
    func progress(at now: Date = Date()) -> Double {
        guard !isCancelledService,
              let departure = expectedDepartureDate,
              let arrival = expectedArrivalDate, arrival > departure else { return 0 }
        let fraction = now.timeIntervalSince(departure) / arrival.timeIntervalSince(departure)
        return min(1, max(0, fraction))
    }
}

// ============================================================================
// MARK: - Extensions
// ============================================================================

extension DarwinServiceModel {
    /// Convert to adapter model for UI compatibility
    func toAdapter(origin: String, destination: String, date: Date) -> DarwinServiceAdapter {
        return DarwinServiceAdapter(from: self, origin: origin, destination: destination, date: date)
    }
}

extension DarwinDepartureBoard {
    /// Convert all train services to adapter models
    func toAdapters(origin: String, destination: String, date: Date) -> [DarwinServiceAdapter] {
        return (trainServices ?? []).map { service in
            service.toAdapter(origin: origin, destination: destination, date: date)
        }
    }
}
