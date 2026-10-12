import Foundation

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
    
    // Official National Rail Live Departure Boards API
    private let baseURL = "https://api1.raildata.org.uk/1010-live-departure-board-dep1_2/LDBWS/api"
    
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
            print("Darwin API Error: \(http.statusCode) for URL: \(url)")
            if let errorString = String(data: data, encoding: .utf8) {
                print("Error response: \(errorString)")
            }
            throw DarwinError.httpError(http.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        // Debug: Print the raw JSON response
        #if DEBUG
        if let jsonString = String(data: data, encoding: .utf8) {
            print("Darwin API Response:\n\(jsonString)")
        }
        #endif
        
        return try decoder.decode(T.self, from: data)
    }
    
    // MARK: - Public API
    
    /// Get live departure board for a station
    /// - Parameters:
    ///   - crs: Station CRS code (e.g. "EUS" for London Euston)
    ///   - date: The date to search (defaults to today)
    ///   - numRows: Number of services to return (default 10)
    ///   - filterCrs: Optional destination filter CRS code
    ///   - filterType: "to" or "from" (default "to")
    ///   - timeOffset: Minutes offset from start of day (default 0)
    ///   - timeWindow: Minutes window to search (default 1439 = all day)
    func departures(
        from crs: String,
        on date: Date = Date(),
        numRows: Int = 10,
        filterCrs: String? = nil,
        filterType: String = "to",
        timeOffset: Int = 0,
        timeWindow: Int = 1439
    ) async throws -> DarwinDepartureBoard {
        // National Rail API uses date in the URL path
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateString = dateFormatter.string(from: date)
        
        // Build the URL: /YYYYMMDD/GetDepartureBoard/{crs}
        var components = URLComponents(string: "\(baseURL)/\(dateString)/GetDepartureBoard/\(crs.uppercased())")!
        
        var queryItems = [
            URLQueryItem(name: "numRows", value: String(numRows))
        ]
        
        if let filterCrs = filterCrs {
            queryItems.append(URLQueryItem(name: "filterCrs", value: filterCrs.uppercased()))
            queryItems.append(URLQueryItem(name: "filterType", value: filterType))
        }
        
        if timeOffset > 0 {
            queryItems.append(URLQueryItem(name: "timeOffset", value: String(timeOffset)))
        }
        
        if timeWindow != 1439 {
            queryItems.append(URLQueryItem(name: "timeWindow", value: String(timeWindow)))
        }
        
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        
        guard let url = components.url else { throw DarwinError.invalidResponse }
        return try await fetch(url)
    }
    
    /// Get arrivals board for a station
    func arrivals(
        at crs: String,
        on date: Date = Date(),
        numRows: Int = 10,
        filterCrs: String? = nil,
        filterType: String = "from",
        timeOffset: Int = 0,
        timeWindow: Int = 1439
    ) async throws -> DarwinDepartureBoard {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateString = dateFormatter.string(from: date)
        
        var components = URLComponents(string: "\(baseURL)/\(dateString)/GetArrivalBoard/\(crs.uppercased())")!
        
        var queryItems = [
            URLQueryItem(name: "numRows", value: String(numRows))
        ]
        
        if let filterCrs = filterCrs {
            queryItems.append(URLQueryItem(name: "filterCrs", value: filterCrs.uppercased()))
            queryItems.append(URLQueryItem(name: "filterType", value: filterType))
        }
        
        if timeOffset > 0 {
            queryItems.append(URLQueryItem(name: "timeOffset", value: String(timeOffset)))
        }
        
        if timeWindow != 1439 {
            queryItems.append(URLQueryItem(name: "timeWindow", value: String(timeWindow)))
        }
        
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        
        guard let url = components.url else { throw DarwinError.invalidResponse }
        return try await fetch(url)
    }
    
    /// Get service details by ID
    func serviceDetails(serviceId: String, on date: Date = Date()) async throws -> DarwinServiceDetails {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateString = dateFormatter.string(from: date)
        
        var components = URLComponents(string: "\(baseURL)/\(dateString)/GetServiceDetails/\(serviceId)")!
        guard let url = components.url else { throw DarwinError.invalidResponse }
        return try await fetch(url)
    }
    
    /// Get next departures between two stations
    func next(
        from origin: String,
        to destination: String,
        on date: Date = Date(),
        numRows: Int = 25
    ) async throws -> DarwinDepartureBoard {
        return try await departures(
            from: origin,
            on: date,
            numRows: numRows,
            filterCrs: destination,
            filterType: "to"
        )
    }
    
    /// Get fastest services between two stations
    func fastest(
        from origin: String,
        to destination: String,
        on date: Date = Date(),
        numRows: Int = 5
    ) async throws -> DarwinDepartureBoard {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateString = dateFormatter.string(from: date)
        
        var components = URLComponents(string: "\(baseURL)/\(dateString)/GetFastestDepartures/\(origin.uppercased())/\(destination.uppercased())")!
        components.queryItems = [
            URLQueryItem(name: "numRows", value: String(numRows))
        ]
        guard let url = components.url else { throw DarwinError.invalidResponse }
        return try await fetch(url)
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
    let nrccMessages: [DarwinMessage]?
}

/// Individual train service
struct DarwinServiceModel: Codable, Identifiable {
    let serviceIdUrlSafe: String?
    let serviceId: String?
    let sta: String?  // Scheduled time of arrival
    let eta: String?  // Estimated time of arrival
    let std: String?  // Scheduled time of departure
    let etd: String?  // Estimated time of departure
    let platform: String?
    let `operator`: String?
    let operatorCode: String?
    let isCircularRoute: Bool?
    let isCancelled: Bool?
    let filterLocationCancelled: Bool?
    let serviceType: Int?
    let length: Int?
    let detachFront: Bool?
    let isReverseFormation: Bool?
    let cancelReason: String?
    let delayReason: String?
    let adhocAlerts: [String]?
    let origin: [DarwinLocation]?
    let destination: [DarwinLocation]?
    let currentOrigins: [DarwinLocation]?
    let currentDestinations: [DarwinLocation]?
    let formation: DarwinFormation?
    
    var id: String {
        serviceIdUrlSafe ?? serviceId ?? UUID().uuidString
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
}

/// Service location (origin/destination)
struct DarwinLocation: Codable {
    let locationName: String?
    let crs: String?
    let via: String?
    let futureChangeTo: String?
    let assocIsCancelled: Bool?
}

/// Train formation details
struct DarwinFormation: Codable {
    let avgLoading: Int?
    let coaches: [DarwinCoach]?
}

/// Individual coach information
struct DarwinCoach: Codable {
    let coachClass: String?
    let loading: Int?
    let number: String?
    let toilet: DarwinToilet?
}

/// Toilet facilities
struct DarwinToilet: Codable {
    let status: Int?
    let value: String?
}

/// Station message (disruption/alert)
struct DarwinMessage: Codable {
    let value: String?
    let category: String?
    let severity: Int?
}

/// Service details response
struct DarwinServiceDetails: Codable {
    let generatedAt: String?
    let serviceType: Int?
    let locationName: String?
    let crs: String?
    let `operator`: String?
    let operatorCode: String?
    let isCancelled: Bool?
    let cancelReason: String?
    let delayReason: String?
    let overdueMessage: String?
    let length: Int?
    let detachFront: Bool?
    let isReverseFormation: Bool?
    let platform: String?
    let sta: String?
    let eta: String?
    let ata: String?  // Actual time of arrival
    let std: String?
    let etd: String?
    let atd: String?  // Actual time of departure
    let adhocAlerts: [String]?
    let previousCallingPoints: [[DarwinCallingPoint]]?
    let subsequentCallingPoints: [[DarwinCallingPoint]]?
}

/// Calling point (station stop)
struct DarwinCallingPoint: Codable, Identifiable {
    let locationName: String?
    let crs: String?
    let st: String?   // Scheduled time
    let et: String?   // Estimated time
    let at: String?   // Actual time
    let isCancelled: Bool?
    let length: Int?
    let detachFront: Bool?
    let adhocAlerts: [String]?
    
    var id: String {
        (crs ?? "") + (st ?? "") + UUID().uuidString
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
// MARK: - Darwin Service Adapter (for UI compatibility)
// ============================================================================

/// Adapter to make Darwin services compatible with existing RTTAPIService/RTTServiceModel
/// This allows Darwin services to work with MyTrainCard and other existing UI components
struct DarwinServiceAdapter: Codable, Identifiable {
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
    
    // Timing
    var scheduledDeparture: String
    var realtimeDeparture: String
    var userSearchDestinationArrivalTime: String?
    var userSearchDestinationScheduledArrivalTime: String?
    
    // Service info
    var platform: String
    var atocName: String?
    var delayMinutes: Int
    var isCancelledService: Bool
    
    // Schedule metadata (for compatibility)
    var scheduleMetadata: ScheduleMetadata?
    
    struct ScheduleMetadata: Codable {
        var identity: String?
        var departureDate: String?
    }
    
    init(from darwinService: DarwinServiceModel, origin: String, destination: String, date: Date) {
        self.id = darwinService.id
        self.serviceID = darwinService.serviceIdUrlSafe ?? darwinService.serviceId ?? UUID().uuidString
        
        self.userSearchOriginCRS = origin
        self.userSearchDestinationCRS = destination
        
        // Origin/Destination
        self.originCRS = origin
        self.originName = darwinService.originName
        self.destinationCRS = destination
        self.destinationName = darwinService.destinationName
        
        // Timing
        self.scheduledDeparture = darwinService.std ?? "N/A"
        self.realtimeDeparture = darwinService.etd ?? darwinService.std ?? "N/A"
        
        // Platform
        self.platform = darwinService.platform ?? "TBC"
        
        // Operator
        self.atocName = darwinService.operator
        
        // Cancellation
        self.isCancelledService = darwinService.isCancelled == true
        
        // Calculate delay
        self.delayMinutes = Self.calculateDelay(
            scheduled: darwinService.std,
            estimated: darwinService.etd
        )
        
        // Schedule metadata
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        self.scheduleMetadata = ScheduleMetadata(
            identity: serviceID,
            departureDate: dateFormatter.string(from: date)
        )
    }
    
    /// Enrich this service with arrival time details from Darwin service details
    mutating func enrichWithServiceDetails(_ details: DarwinServiceDetails) {
        // Find the destination calling point in subsequent calling points
        if let callingPoints = details.subsequentCallingPoints?.flatMap({ $0 }),
           let destPoint = callingPoints.first(where: { $0.crs == userSearchDestinationCRS }) {
            
            // Use actual > estimated > scheduled
            if let at = destPoint.at {
                self.userSearchDestinationArrivalTime = at
            } else if let et = destPoint.et {
                self.userSearchDestinationArrivalTime = et
            } else if let st = destPoint.st {
                self.userSearchDestinationArrivalTime = st
                self.userSearchDestinationScheduledArrivalTime = st
            }
        } else {
            // Fallback: estimate based on departure + 1 hour
            let departureTimeStr = scheduledDeparture
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm"
            if let depTime = dateFormatter.date(from: departureTimeStr) {
                let estimatedArrival = depTime.addingTimeInterval(3600) // +1 hour
                self.userSearchDestinationArrivalTime = dateFormatter.string(from: estimatedArrival)
            } else {
                self.userSearchDestinationArrivalTime = "--:--"
            }
        }
    }
    
    private static func calculateDelay(scheduled: String?, estimated: String?) -> Int {
        guard let sched = scheduled, let est = estimated, est != "On time" else {
            return 0
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        
        guard let schedTime = formatter.date(from: sched),
              let estTime = formatter.date(from: est) else {
            return 0
        }
        
        let delaySeconds = estTime.timeIntervalSince(schedTime)
        return max(0, Int(delaySeconds / 60))
    }
    
    /// Convert to TrainJourney for the detail view (compatible with RTTAPIService extension)
    func toTrainJourney() -> TrainJourney {
        let originCode = userSearchOriginCRS ?? (originCRS.isEmpty ? "UNK" : originCRS)
        let destCode = userSearchDestinationCRS ?? (destinationCRS.isEmpty ? "UNK" : destinationCRS)
        
        let originStation = TrainStation(code: originCode, name: originName, scheduled: scheduledDeparture, actual: realtimeDeparture)
        let destStation = TrainStation(code: destCode, name: destinationName, scheduled: userSearchDestinationArrivalTime ?? scheduledDeparture, actual: userSearchDestinationArrivalTime ?? scheduledDeparture)
        
        return TrainJourney(
            origin: originStation,
            destination: destStation,
            scheduledDeparture: "\(scheduledDeparture) \(originCode)-\(destCode)",
            predictedArrival: userSearchDestinationArrivalTime ?? scheduledDeparture,
            actualArrival: userSearchDestinationArrivalTime ?? scheduledDeparture,
            delayMinutes: delayMinutes,
            platform: platform,
            trainType: atocName ?? "Unknown Service"
        )
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
