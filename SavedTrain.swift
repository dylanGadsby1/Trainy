import Foundation
import SwiftData

@Model
final class SavedTrain {
    var id: String
    var isPast: Bool
    var addedAt: Date
    var serviceData: Data
    
    init(id: String, isPast: Bool = false, serviceData: Data) {
        self.id = id
        self.isPast = isPast
        self.serviceData = serviceData
        self.addedAt = Date()
    }
    
    var service: RTTAPIService? {
        try? JSONDecoder().decode(RTTAPIService.self, from: serviceData)
    }
}
