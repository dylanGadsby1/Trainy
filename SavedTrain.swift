import Foundation
import SwiftData

@Model
final class SavedTrain {
    var id: String
    var isPast: Bool
    var addedAt: Date
    var serviceData: Data
    /// Set to the real (with-delay) arrival time when the train is moved to Rail History.
    var movedToPastAt: Date?
    /// When the user marked this journey's Delay Repay as claimed
    var delayRepayClaimedAt: Date?
    
    init(id: String, isPast: Bool = false, serviceData: Data) {
        self.id = id
        self.isPast = isPast
        self.serviceData = serviceData
        self.addedAt = Date()
        self.movedToPastAt = nil
    }
    
    /// The last decoded `serviceData`. Views read `service` several times a redraw, so decode once per change.
    @Transient private var decoded: (data: Data, service: DarwinServiceAdapter?)? = nil

    var service: DarwinServiceAdapter? {
        if let decoded, decoded.data == serviceData { return decoded.service }
        let service = Self.decode(serviceData)
        decoded = (serviceData, service)
        return service
    }

    private static func decode(_ data: Data) -> DarwinServiceAdapter? {
        let decoder = JSONDecoder()
        if let train = try? decoder.decode(DarwinServiceAdapter.self, from: data) {
            return train
        }
        // Trains saved before the Darwin migration were stored as RTT models
        return (try? decoder.decode(RTTServiceModel.self, from: data)).map(DarwinServiceAdapter.init(legacy:))
    }
}

// MARK: - Delay Repay

/// The Delay Repay claim a past journey qualifies for: who to claim from and how long is left.
struct DelayRepayClaim {
    /// Operators accept claims for 28 days after the journey
    static let claimWindowDays = 28

    let brand: OperatorBrand
    let url: URL
    let delayMinutes: Int
    let isCancelled: Bool
    let deadline: Date
    let claimedAt: Date?

    /// Still worth the user's attention: not claimed, and the operator would still accept it
    var isOpen: Bool { claimedAt == nil && Date() < deadline }

    /// Whole days until the deadline; 0 on the last day
    var daysLeft: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0)
    }

    var daysLeftText: String {
        switch daysLeft {
        case 0: return "Last day to claim"
        case 1: return "1 day left"
        default: return "\(daysLeft) days left"
        }
    }
}

extension SavedTrain {
    /// Nil when the journey was not late enough, or its operator has no Delay Repay page.
    var delayRepay: DelayRepayClaim? {
        guard isPast, let service,
              let brand = OperatorBrand.from(code: service.atocCode),
              let url = brand.delayRepayURL.flatMap({ URL(string: $0) }),
              service.isCancelledService || service.delayMinutes >= brand.delayRepayThreshold else { return nil }

        let travelled = service.scheduledDepartureDate ?? movedToPastAt ?? addedAt
        let deadline = Calendar.current.date(byAdding: .day, value: DelayRepayClaim.claimWindowDays, to: travelled) ?? travelled

        return DelayRepayClaim(
            brand: brand,
            url: url,
            delayMinutes: service.delayMinutes,
            isCancelled: service.isCancelledService,
            deadline: deadline,
            claimedAt: delayRepayClaimedAt
        )
    }
}

// MARK: - Saved Routes

/// A journey the user makes often, kept so it can be searched in one tap.
@Model
final class SavedRoute {
    var originCRS: String
    var destinationCRS: String
    var addedAt: Date

    init(originCRS: String, destinationCRS: String) {
        self.originCRS = originCRS
        self.destinationCRS = destinationCRS
        self.addedAt = Date()
    }

    var origin: UKStation? { ukStations.first { $0.crs == originCRS } }
    var destination: UKStation? { ukStations.first { $0.crs == destinationCRS } }
}
