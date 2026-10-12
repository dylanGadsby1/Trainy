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
