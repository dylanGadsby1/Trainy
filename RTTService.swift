import Foundation

// MARK: - Realtime Trains API Service

final class RTTService {

    static let shared = RTTService()
    private init() {}

    // ── Credentials ──────────────────────────────────────────────────────────
    // Refresh token provided by user for Next Generation API
    private let refreshToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI4MTE4NzIzZC00M2FjLTRlMTMtYThiMi02YzhkMWRjYmNjZTIiLCJpc3MiOiJodHRwczovL2FwaS1wb3J0YWwucnR0LmlvIn0.K6_AWC4WdUdkx5GebMotjifGjHG21Z5cLkFP-LIVKsg"
    
    // In-memory access token cache
    private var accessToken: String?

    // Base URL for Next Generation API
    private let baseURL = "https://data.rtt.io"

    // MARK: - URL Session

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    // MARK: - Auth Logic

    private func getValidAccessToken() async throws -> String {
        if let token = accessToken {
            // In a production app, we would check the 'validUntil' expiry time here.
            // For now, we rely on the 401 Unauthorized catch to refresh it if it expires.
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
        
        // The token exchange returns a JSON with a "token" field
        struct TokenResponse: Decodable {
            let token: String
        }
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(TokenResponse.self, from: data)
        self.accessToken = result.token
        return result.token
    }

    // MARK: - Generic Fetch

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        let token = try await getValidAccessToken()
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw RTTError.invalidResponse
        }
        
        // If token expired, we can clear it and throw an error to be handled, or retry
        if http.statusCode == 401 {
            self.accessToken = nil
            throw RTTError.authFailed // The caller could theoretically retry, but for simplicity we throw
        }
        
        guard http.statusCode == 200 else {
            print("API Error: \(http.statusCode) for URL: \(url)")
            throw RTTError.httpError(http.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Public API
    
    /// Departures from a station for today.
    func departures(from crs: String, to destination: String? = nil) async throws -> RTTSearchResponse {
        var components = URLComponents(string: "\(baseURL)/gb-nr/location")!
        var queryItems = [URLQueryItem(name: "code", value: crs.uppercased())]
        if let dest = destination {
            queryItems.append(URLQueryItem(name: "filterTo", value: dest.uppercased()))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw RTTError.invalidResponse }
        return try await fetch(url)
    }



    /// Departures from a station for a specific date.
    func departures(from origin: String, on date: Date, to destination: String) async throws -> RTTSearchResponse {
        var components = URLComponents(string: "\(baseURL)/gb-nr/location")!
        components.queryItems = [
            URLQueryItem(name: "code", value: origin),
            URLQueryItem(name: "filterTo", value: destination),
            URLQueryItem(name: "detailed", value: "true"),
            URLQueryItem(name: "timeFrom", value: isoString(date))
        ]
        guard let url = components.url else { throw RTTError.invalidResponse }
        return try await fetch(url)
    }



    /// Service details for a specific train and date.
    func serviceDetails(identity: String, date: String) async throws -> RTTServiceDetailResponse {
        guard let url = URL(string: "\(baseURL)/gb-nr/service?identity=\(identity)&departureDate=\(date)") else {
            throw RTTError.invalidResponse
        }
        return try await fetch(url)
    }

    // MARK: - Helpers

    private func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

// MARK: - RTT Errors

enum RTTError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case authFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:   return "Invalid server response."
        case .httpError(let c):  return "Server returned HTTP \(c)."
        case .authFailed:        return "Authentication failed with Realtime Trains API."
        }
    }
}
