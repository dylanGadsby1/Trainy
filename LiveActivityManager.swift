import Foundation
import ActivityKit
import SwiftUI
import Combine

@Observable
class LiveActivityManager {
    static let shared = LiveActivityManager()

    var currentActivity: Activity<TrainyActivityAttributes>?
    private var updateTimer: AnyCancellable?
    private var currentService: DarwinServiceAdapter?

    func startTracking(service: DarwinServiceAdapter) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live activities are not enabled.")
            return
        }

        // End any existing
        endTracking()

        // The Live Activity shows the user's journey, not the train's full route
        let attributes = TrainyActivityAttributes(
            trainId: service.id,
            originName: stationName(for: service.originCRS) ?? service.originName,
            originCRS: service.originCRS,
            destinationName: stationName(for: service.destinationCRS) ?? service.destinationName,
            destinationCRS: service.destinationCRS,
            operatorCode: service.atocCode ?? "NA"
        )

        currentActivity = try? Activity.request(
            attributes: attributes,
            content: .init(state: contentState(for: service), staleDate: nil)
        )
        currentService = service
        print("Started Live Activity: \(currentActivity?.id ?? "")")

        // Start polling every 30 seconds
        startPolling()
    }

    func updateTracking(with service: DarwinServiceAdapter) {
        // Matched by journey, because a train's id changes when it moves from the timetable to Darwin
        guard let activity = currentActivity, currentService?.isSameJourney(as: service) == true else { return }

        currentService = service
        let state = contentState(for: service)

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    /// Ends the Live Activity if it is tracking the given train.
    func endTracking(for train: DarwinServiceAdapter) {
        guard currentService?.isSameJourney(as: train) == true else { return }
        endTracking()
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
        currentService = nil
        updateTimer?.cancel()
        updateTimer = nil
    }

    private func contentState(for service: DarwinServiceAdapter) -> TrainyActivityAttributes.ContentState {
        TrainyActivityAttributes.ContentState(
            scheduledDeparture: service.scheduledDeparture,
            expectedDeparture: service.realtimeDeparture,
            delayMinutes: service.delayMinutes,
            platform: service.platform,
            isCancelled: service.isCancelledService
        )
    }

    private func stationName(for crs: String) -> String? {
        ukStations.first { $0.crs == crs }?.name
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
        guard let service = currentService else { return }

        Task { @MainActor in
            if let updated = await TrainSync.shared.refreshed(service) {
                updateTracking(with: updated)
            }
        }
    }
}
