import Foundation
import SwiftData

// Every stored property has a default or is optional, and none is unique: iCloud sync
// (CloudSync.swift) needs both.

@Model
final class SavedTrain {
    var id: String = ""
    var isPast: Bool = false
    /// Also decides which copy is kept when two devices saved the same train (CloudSync)
    var addedAt: Date = Date()
    var serviceData: Data = Data()
    /// Set to the real (with-delay) arrival time when the train is moved to Rail History.
    var movedToPastAt: Date?
    /// When the user marked this journey's Delay Repay as claimed
    var delayRepayClaimedAt: Date?

    // A journey with a change (see JourneyPlanner.swift). Nil on a train followed on its own.
    /// Shared by every train of one journey
    var journeyID: String?
    /// Where this train comes in the journey, counting from 0
    var legIndex: Int = 0
    /// The whole journey, "Newcastle to Bristol Temple Meads"
    var journeyTitle: String?
    /// How to reach this train from the one before, or from the start, when that is more
    /// than stepping across a station: "Tube from King's Cross St. Pancras to Paddington"
    var transferNote: String?
    /// How long the planner allowed for the change onto this train, in minutes
    var transferMinutes: Int?
    /// What is left to do after the last train: "Walk to Brighton"
    var onwardNote: String?
    /// The Tube lines the change onto this train uses, comma-separated, for showing how they are running
    var transferLines: String?
    /// The platform this train is timetabled to arrive at, where the next change starts
    var arrivalPlatform: String?
    /// When the journey was due to end as first planned. A missed connection can change the
    /// trains, and Delay Repay goes by how late the traveller was against the original plan.
    var journeyPlannedArrival: Date?
    /// The operator whose train first broke the journey as planned, by its two-letter code:
    /// the one a Delay Repay claim for the journey goes to. Nil on a journey that ran as planned.
    var journeyDisruptedBy: String?
    
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

extension SavedTrain {
    /// Gets the reminders an hour and five minutes before it leaves. Only the first train of a
    /// journey with a change does: the reminder on the way into each change covers the rest.
    var remindsBeforeDeparture: Bool { legIndex == 0 }
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
    /// The claim is for a journey of several trains, by how late it ended, not for one train
    var isJourney = false

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
    var originCRS: String = ""
    var destinationCRS: String = ""
    var addedAt: Date = Date()

    // Commute (see CommuteMode.swift). The defaults let routes saved before this was added load.
    /// The days the route is commuted on, one bit each: Sunday is 1, Monday 2, up to Saturday 64.
    /// 0 when the route is not a commute.
    var commuteDays: Int = 0
    /// When the usual train leaves, in minutes after midnight, UK time
    var commuteMinutes: Int = 0
    /// The day ("yyyy-MM-dd") of the last commute a train was followed for, so that a train
    /// the user then removes is not put back
    var lastCommuteDay: String?

    init(originCRS: String, destinationCRS: String) {
        self.originCRS = originCRS
        self.destinationCRS = destinationCRS
        self.addedAt = Date()
    }

    var origin: UKStation? { ukStations.first { $0.crs == originCRS } }
    var destination: UKStation? { ukStations.first { $0.crs == destinationCRS } }
}
