import Foundation
import SwiftUI

// MARK: - Type Alias for backward compatibility
// NOTE: These typealiases are commented out due to conflicts with the original RTT API models
// Instead, we use protocol-based UI components that work with both RTT and Darwin services
// typealias RTTAPIService = DarwinServiceAdapter
// typealias RTTServiceModel = DarwinServiceAdapter

// MARK: - Train Service Protocol
// This protocol allows both RTT and Darwin service models to work with shared UI components
protocol TrainServiceModel {
    var id: String { get }
    var atocCode: String? { get }
    var atocName: String? { get }
    var trainStatus: TrainStatus { get }
    var userSearchOriginCRS: String? { get }
    var originCRS: String { get }
    var scheduledDeparture: String { get }
    var delayMinutes: Int { get }
    var realtimeDeparture: String { get }
    var userSearchDestinationCRS: String? { get }
    var destinationCRS: String { get }
    var userSearchDestinationArrivalTime: String? { get }
    var userSearchDestinationScheduledArrivalTime: String? { get }
    var platform: String { get }
    
    func toTrainJourney() -> TrainJourney
}

// MARK: - Train Status
enum TrainStatus: Equatable {
    case onTime
    case delayed
    case cancelled
    
    var label: String {
        switch self {
        case .onTime: return "ON TIME"
        case .delayed: return "DELAYED"
        case .cancelled: return "CANCELLED"
        }
    }
    
    var color: Color {
        switch self {
        case .onTime: return .green
        case .delayed: return .orange
        case .cancelled: return Color(red: 0.95, green: 0.25, blue: 0.25)
        }
    }
}

// MARK: - Darwin → RTT Adapter Models
// These models adapt Darwin's data structure to work with your existing UI

/// Adapter to make Darwin services compatible with existing RTTAPIService/RTTServiceModel
/// This allows Darwin services to work with MyTrainCard and other existing UI components
struct DarwinServiceAdapter: Codable, Identifiable, TrainServiceModel {
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
    var atocCode: String?
    var delayMinutes: Int
    var isCancelledService: Bool
    
    // Schedule metadata (for compatibility)
    var scheduleMetadata: ScheduleMetadata?
    
    struct ScheduleMetadata: Codable {
        var identity: String?
        var departureDate: String?
    }
    
    // MARK: - Computed Properties
    
    /// Train status computed from cancellation and delay info
    var trainStatus: TrainStatus {
        if isCancelledService {
            return .cancelled
        } else if delayMinutes > 0 {
            return .delayed
        } else {
            return .onTime
        }
    }
    
    // MARK: - Initializer
    
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
        self.atocCode = darwinService.operatorCode
        
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

