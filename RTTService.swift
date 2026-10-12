import Foundation

// MARK: - Realtime Trains API Service
// Realtime Trains holds the timetable, so it covers trains Darwin does not list yet
// (more than about four hours ahead) and trains Darwin has already dropped.

actor RTTService {

    static let shared = RTTService()
    private init() {}

    // ── Credentials ──────────────────────────────────────────────────────────
    // Refresh token provided by user for Next Generation API
    private let refreshToken = Secrets.rttRefreshToken

    // In-memory access token cache
    private var accessToken: String?
    private var accessTokenExpiry: Date?

    /// Set when the API answers 429, so no further requests go out until it lifts.
    /// The key allows 10 requests a minute and 100 an hour.
    private var rateLimitedUntil: Date?

    // Base URL for Next Generation API
    private let baseURL = "https://data.rtt.io"

    // MARK: - URL Session

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    // MARK: - Auth Logic

    private func getValidAccessToken() async throws -> String {
        // Access tokens last about twenty minutes; renew a minute early
        if let token = accessToken, let expiry = accessTokenExpiry, expiry.timeIntervalSinceNow > 60 {
            return token
        }
        return try await fetchNewAccessToken()
    }

    private func fetchNewAccessToken() async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/get_access_token") else {
            throw RTTError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(refreshToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RTTError.authFailed
        }

        struct TokenResponse: Decodable {
            let token: String
            let validUntil: String?
        }

        let result = try JSONDecoder().decode(TokenResponse.self, from: data)
        self.accessToken = result.token
        self.accessTokenExpiry = result.validUntil.flatMap { ISO8601DateFormatter().date(from: $0) }
            ?? Date().addingTimeInterval(10 * 60)
        return result.token
    }

    // MARK: - Generic Fetch

    /// Returns nil when the query is valid but matches nothing (HTTP 204).
    private func fetch<T: Decodable>(_ path: String, query: [URLQueryItem], retryingAuth: Bool = true) async throws -> T? {
        if let until = rateLimitedUntil, until > Date() {
            throw RTTError.rateLimitExceeded
        }

        var request: URLRequest
        if let relayed = TrainyServer.request("rtt\(path)", query: query) {
            // With a Trainy server the timetable comes through it, and the token stays there
            request = relayed
        } else {
            let token = try await getValidAccessToken()

            var components = URLComponents(string: "\(baseURL)\(path)")
            components?.queryItems = query
            guard let url = components?.url else { throw RTTError.invalidResponse }

            request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        }
        guard let url = request.url else { throw RTTError.invalidResponse }

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw RTTError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                print("❌ RTT decoding error for URL \(url): \(error)")
                throw error
            }
        case 204:
            return nil
        case 401 where retryingAuth:
            // The access token expired early: get a new one and try once more
            accessToken = nil
            return try await fetch(path, query: query, retryingAuth: false)
        case 401:
            throw RTTError.authFailed
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 60
            rateLimitedUntil = Date().addingTimeInterval(retryAfter)
            print("⚠️ RTT rate limit reached. Pausing requests for \(Int(retryAfter))s.")
            throw RTTError.rateLimitExceeded
        default:
            print("❌ RTT API Error: \(http.statusCode) for URL: \(url)")
            throw RTTError.httpError(http.statusCode)
        }
    }

    // MARK: - API Requests

    /// Trains calling at `origin` and then `destination`, departing in the window after `date`.
    func departures(from origin: String, to destination: String, from date: Date, window: Int) async throws -> RTTSearchResponse? {
        try await fetch("/gb-nr/location", query: [
            URLQueryItem(name: "code", value: origin.uppercased()),
            URLQueryItem(name: "filterTo", value: destination.uppercased()),
            URLQueryItem(name: "timeFrom", value: Self.timeFormatter.string(from: date)),
            URLQueryItem(name: "timeWindow", value: String(window))
        ])
    }

    /// Trains arriving at `destination` between two times, having called at `origin`.
    func arrivals(at destination: String, from origin: String, from start: Date, until end: Date) async throws -> RTTSearchResponse? {
        try await fetch("/gb-nr/location", query: [
            URLQueryItem(name: "code", value: destination.uppercased()),
            URLQueryItem(name: "filterFrom", value: origin.uppercased()),
            URLQueryItem(name: "timeFrom", value: Self.timeFormatter.string(from: start)),
            URLQueryItem(name: "timeTo", value: Self.timeFormatter.string(from: end))
        ])
    }

    /// Every calling point of one train. `uniqueIdentity` looks like "gb-nr:Y80917:2026-10-12".
    func service(uniqueIdentity: String) async throws -> RTTServiceDetailResponse? {
        let parts = uniqueIdentity.split(separator: ":").map(String.init)
        guard parts.count == 3 else { throw RTTError.invalidResponse }
        return try await fetch("/\(parts[0])/service", query: [
            URLQueryItem(name: "identity", value: parts[1]),
            URLQueryItem(name: "departureDate", value: parts[2])
        ])
    }

    // MARK: - Trains

    /// Timetabled trains from `origin` to `destination` leaving in the `window` minutes after `date`.
    /// Two requests: the origin's departures, then the destination's arrivals for the arrival times.
    func search(from origin: String, to destination: String, at date: Date, window: Int = 360) async throws -> [DarwinServiceAdapter] {
        guard let departures = try await departures(from: origin, to: destination, from: date, window: window) else {
            return []
        }

        // The last of these trains reaches the destination no later than it reaches its own terminus
        let lastArrival = (departures.services ?? [])
            .compactMap { $0.destination?.last?.temporalData?.scheduleAdvertised }
            .max()
            .flatMap { Self.timeFormatter.date(from: $0) }
            ?? date.addingTimeInterval(TimeInterval((window + 360) * 60))
        // A query can span at most 23 hours 59 minutes
        let end = min(lastArrival.addingTimeInterval(10 * 60), date.addingTimeInterval(1439 * 60))

        // Arrival times are a bonus: the search still works without them
        let arrivals = try? await arrivals(at: destination, from: origin, from: date, until: end)

        return Self.trains(departures: departures, arrivals: arrivals, origin: origin, destination: destination)
    }

    /// Joins an origin's departures to a destination's arrivals, train by train.
    nonisolated static func trains(
        departures: RTTSearchResponse,
        arrivals: RTTSearchResponse?,
        origin: String,
        destination: String
    ) -> [DarwinServiceAdapter] {
        var arrivalByTrain: [String: RTTTimeNode] = [:]
        for service in arrivals?.services ?? [] {
            if let identity = service.scheduleMetadata?.uniqueIdentity, let arrival = service.temporalData?.arrival {
                arrivalByTrain[identity] = arrival
            }
        }

        return (departures.services ?? []).compactMap { service in
            // Passenger trains only, to match what Darwin's train board lists
            guard service.scheduleMetadata?.inPassengerService != false,
                  (service.scheduleMetadata?.modeType ?? "TRAIN") == "TRAIN",
                  let identity = service.scheduleMetadata?.uniqueIdentity else { return nil }
            return DarwinServiceAdapter(rtt: service, arrival: arrivalByTrain[identity], origin: origin, destination: destination)
        }
    }

    /// `train` with Realtime Trains' current times applied, or nil if they could not be read.
    func refreshed(_ train: DarwinServiceAdapter) async -> DarwinServiceAdapter? {
        guard let identity = train.rttIdentity,
              let response = try? await service(uniqueIdentity: identity) else { return nil }
        return Self.applying(response, to: train)
    }

    nonisolated static func applying(_ response: RTTServiceDetailResponse, to train: DarwinServiceAdapter) -> DarwinServiceAdapter? {
        let calls = response.service?.locations ?? []
        let origin = train.userSearchOriginCRS ?? train.originCRS
        let destination = train.userSearchDestinationCRS ?? train.destinationCRS

        // A circular route can call at the origin twice, so prefer the call at the scheduled time
        guard let from = calls.firstIndex(where: {
            $0.isCall(at: origin) && $0.temporalData?.departure?.scheduledClock == train.scheduledDeparture
        }) ?? calls.firstIndex(where: { $0.isCall(at: origin) }) else { return nil }

        let to = calls[(from + 1)...].firstIndex { $0.isCall(at: destination) }

        var updated = train
        updated.applyRTT(
            departure: calls[from].temporalData?.departure,
            arrival: to.flatMap { calls[$0].temporalData?.arrival },
            platform: calls[from].locationMetadata?.platform
        )
        if let to {
            updated.stops = calls[from...to].enumerated().compactMap { offset, call in
                // The two ends keep the codes the user searched with
                let crs = offset == 0 ? origin : (offset == to - from ? destination : nil)
                return DarwinServiceAdapter.Stop(rtt: call, crs: crs, isLast: offset == to - from)
            }
        }
        return updated
    }

    /// Finds the Realtime Trains identity of a train that was found through Darwin.
    func identity(for train: DarwinServiceAdapter) async -> String? {
        // This key can only see the last 14 days
        guard let departure = train.scheduledDepartureDate,
              departure.timeIntervalSinceNow > -13 * 86400,
              let response = try? await departures(
                from: train.userSearchOriginCRS ?? train.originCRS,
                to: train.userSearchDestinationCRS ?? train.destinationCRS,
                from: departure.addingTimeInterval(-60),
                window: 3
              ) else { return nil }

        let sameMinute = (response.services ?? []).filter {
            $0.temporalData?.departure?.scheduledClock == train.scheduledDeparture
        }
        let match = sameMinute.first { $0.atocCode == train.atocCode } ?? (sameMinute.count == 1 ? sameMinute.first : nil)
        return match?.scheduleMetadata?.uniqueIdentity
    }

    // MARK: - Helpers

    /// Realtime Trains reads a time without an offset as local to the station, so send UK time.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
}

// MARK: - RTT Errors

enum RTTError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case authFailed
    case rateLimitExceeded

    var errorDescription: String? {
        switch self {
        case .invalidResponse:   return "Invalid server response."
        case .httpError(let c):  return "Server returned HTTP \(c)."
        case .authFailed:        return "Authentication failed with Realtime Trains API."
        case .rateLimitExceeded: return "Too many requests. Please wait a moment and try again."
        }
    }
}
