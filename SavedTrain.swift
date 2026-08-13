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
    
    init(id: String, isPast: Bool = false, serviceData: Data) {
        self.id = id
        self.isPast = isPast
        self.serviceData = serviceData
        self.addedAt = Date()
        self.movedToPastAt = nil
    }
    
    var service: RTTAPIService? {
        try? JSONDecoder().decode(RTTAPIService.self, from: serviceData)
    }
}
