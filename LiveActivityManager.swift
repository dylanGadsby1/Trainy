import Foundation
import ActivityKit
import SwiftUI
import Combine

@Observable
class LiveActivityManager {
    static let shared = LiveActivityManager()
    
    var currentActivity: Activity<TrainyActivityAttributes>?
    private var updateTimer: AnyCancellable?
    private var currentServiceId: String?
    
    func startTracking(service: RTTServiceModel) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live activities are not enabled.")
            return
        }
        
        // End any existing
        endTracking()
        
        let attributes = TrainyActivityAttributes(
            trainId: service.id,
            originName: service.originName,
            originCRS: service.originCRS,
            destinationName: service.destinationName,
            destinationCRS: service.destinationCRS,
            operatorCode: service.atocCode ?? "NA"
        )
        
        let state = TrainyActivityAttributes.ContentState(
            scheduledDeparture: service.scheduledDeparture,
            expectedDeparture: service.realtimeDeparture,
            delayMinutes: service.delayMinutes,
            platform: service.platform,
            isCancelled: service.isCancelledService
        )
        
        currentActivity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil)
        )
        currentServiceId = service.id
        print("Started Live Activity: \(currentActivity?.id ?? "")")
        
        // Start polling every 30 seconds
        startPolling()
    }
    
    func updateTracking(with service: RTTServiceModel) {
        guard let activity = currentActivity else { return }
        
        let state = TrainyActivityAttributes.ContentState(
            scheduledDeparture: service.scheduledDeparture,
            expectedDeparture: service.realtimeDeparture,
            delayMinutes: service.delayMinutes,
            platform: service.platform,
            isCancelled: service.isCancelledService
        )
        
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }
    
    func endTracking() {
        guard let activity = currentActivity else { return }
        
        Task {
            let state = TrainyActivityAttributes.ContentState(
                scheduledDeparture: "--:--",
                expectedDeparture: "--:--",
                delayMinutes: 0,
                platform: "",
                isCancelled: false
            )
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
        currentActivity = nil
        currentServiceId = nil
        updateTimer?.cancel()
        updateTimer = nil
    }
    
    private func startPolling() {
        updateTimer?.cancel()
        
        // Poll every 30 seconds while app is in foreground
        updateTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchAndUpdate()
            }
    }
    
    private func fetchAndUpdate() {
        guard currentServiceId != nil else { return }
        
        Task {
            // Note: RTTService.shared.fetchServiceDetails requires URL params. 
            // We might need to construct the URL or fetch by ID. 
            // For now, this is a placeholder for the actual refresh logic.
            // A more robust implementation would store the full request URL in the manager.
            print("Polling for Live Activity update...")
        }
    }
}
