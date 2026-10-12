import Foundation
import ActivityKit
import SwiftUI
import Combine

@MainActor
@Observable
class LiveActivityManager {
    static let shared = LiveActivityManager()

    var currentActivity: Activity<TrainyActivityAttributes>?
    private var updateTimer: AnyCancellable?
    private var currentService: DarwinServiceAdapter?
    /// Passes the activity's push address on to the Trainy server as iOS issues it
    private var pushTokenTask: Task<Void, Never>?

    func startTracking(service: DarwinServiceAdapter) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live activities are not enabled.")
            return
        }

        // One at a time: end any other
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

        // With a Trainy server the activity is also updated by push, which reaches it
        // while the app is closed
        let activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: contentState(for: service), staleDate: nil),
            pushType: TrainyServer.shared.canPushLiveActivities ? .token : nil
        )
        print("Started Live Activity: \(activity?.id ?? "")")

        if let activity {
            follow(activity, showing: service)
        }
    }

    func updateTracking(with service: DarwinServiceAdapter) {
        // An activity started before the app was last closed is still on the Lock Screen,
        // though this object no longer holds it: pick it up again
        if currentActivity == nil, let running = activities(showing: service).first {
            follow(running, showing: service)
        }

        // Matched by journey, because a train's id changes when it moves from the timetable to Darwin
        guard let activity = currentActivity, currentService?.isSameJourney(as: service) == true else { return }

        currentService = service
        let state = contentState(for: service)

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    /// Ends the Live Activity showing the given train, if there is one.
    func endTracking(for train: DarwinServiceAdapter) {
        for activity in activities(showing: train) {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        if currentService?.isSameJourney(as: train) == true {
            stopFollowing()
        }
    }

    /// Ends every Live Activity, including one this object lost track of when the app closed.
    func endTracking() {
        for activity in Activity<TrainyActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        stopFollowing()
    }

    /// Keeps `activity` up to date while the app is open, and hands its push address to
    /// the Trainy server so it is kept up to date while the app is closed.
    private func follow(_ activity: Activity<TrainyActivityAttributes>, showing service: DarwinServiceAdapter) {
        currentActivity = activity
        currentService = service
        startPolling()

        pushTokenTask?.cancel()
        guard TrainyServer.shared.canPushLiveActivities else { return }

        let journeyKey = service.journeyKey
        pushTokenTask = Task { @MainActor in
            for await token in activity.pushTokenUpdates {
                TrainyServer.shared.setLiveActivity(
                    journeyKey: journeyKey,
                    token: token.map { String(format: "%02x", $0) }.joined()
                )
            }
        }
    }

    private func stopFollowing() {
        if let service = currentService, pushTokenTask != nil {
            TrainyServer.shared.setLiveActivity(journeyKey: service.journeyKey, token: nil)
        }
        pushTokenTask?.cancel()
        pushTokenTask = nil
        currentActivity = nil
        currentService = nil
        updateTimer?.cancel()
        updateTimer = nil
    }

    /// The running activities for a train, found by what they show.
    private func activities(showing service: DarwinServiceAdapter) -> [Activity<TrainyActivityAttributes>] {
        Activity<TrainyActivityAttributes>.activities.filter {
            $0.attributes.originCRS == service.originCRS
                && $0.attributes.destinationCRS == service.destinationCRS
                && $0.content.state.scheduledDeparture == service.scheduledDeparture
        }
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
