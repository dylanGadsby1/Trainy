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

    // MARK: - A Journey of Several Trains

    /// Marks an activity as a journey's in its `trainId`, ahead of the journey's own id
    private static let journeyPrefix = "journey:"

    /// One activity for a whole journey: it shows the train the traveller is on, or is
    /// waiting for, and what comes after it, and moves on from train to train.
    func startTracking(journey: SavedJourney) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live activities are not enabled.")
            return
        }
        guard let state = journeyState(journey),
              let first = journey.services.first, let last = journey.services.last else { return }

        // One at a time: end any other
        endTracking()

        let origin = first.userSearchOriginCRS ?? first.originCRS
        let destination = last.userSearchDestinationCRS ?? last.destinationCRS
        let attributes = TrainyActivityAttributes(
            trainId: Self.journeyPrefix + journey.id,
            originName: stationName(for: origin) ?? origin,
            originCRS: origin,
            destinationName: stationName(for: destination) ?? destination,
            destinationCRS: destination,
            operatorCode: first.atocCode ?? "NA"
        )

        // Kept up to date by the app alone: a Trainy server follows trains one at a time,
        // and does not know which belong to one journey
        let activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil),
            pushType: nil
        )
        print("Started journey Live Activity: \(activity?.id ?? "")")
    }

    /// Brings a journey's activity up to date after a sync: on to the next train once one
    /// is done, and ended when the journey is, or when its trains are no longer followed.
    func updateJourney(with trains: [SavedTrain]) {
        // Found among the running activities, so one started before the app last closed is picked up
        for activity in Activity<TrainyActivityAttributes>.activities where activity.attributes.trainId.hasPrefix(Self.journeyPrefix) {
            let id = String(activity.attributes.trainId.dropFirst(Self.journeyPrefix.count))
            let legs = trains
                .filter { $0.journeyID == id && $0.modelContext != nil && !$0.isDeleted && $0.service != nil }
                .sorted { $0.legIndex < $1.legIndex }

            guard legs.contains(where: { !$0.isPast }), let state = journeyState(SavedJourney(id: id, legs: legs)) else {
                Task { await activity.end(nil, dismissalPolicy: .default) }
                continue
            }
            guard state != activity.content.state else { continue }
            Task { await activity.update(.init(state: state, staleDate: nil)) }
        }
    }

    /// What a journey's activity shows: the times and platform of the current train, with
    /// which train that is and what comes next.
    private func journeyState(_ journey: SavedJourney) -> TrainyActivityAttributes.ContentState? {
        guard let current = journey.currentLeg() else { return nil }
        var state = contentState(for: current)

        let destination = current.userSearchDestinationCRS ?? current.destinationCRS
        state.legSummary = "\(UKStation.name(for: current.userSearchOriginCRS ?? current.originCRS)) to \(UKStation.name(for: destination))"

        if let index = journey.legs.firstIndex(where: { $0.service?.isSameJourney(as: current) == true }),
           let connection = journey.connection(before: index + 1) {
            // Short enough for one line on the Lock Screen: where the next train goes from
            var parts = ["\(connection.warning ?? "Change") at \(connection.station)"]
            if let minutes = connection.minutes, connection.state != .broken {
                parts.append("\(max(0, minutes)) min")
            }
            if !connection.departing.platform.isEmpty, connection.departing.platform != "TBC" {
                parts.append("Platform \(connection.departing.platform)")
            }
            state.nextStep = parts.joined(separator: " · ")
        } else {
            let arrival = current.userSearchDestinationArrivalTime ?? current.userSearchDestinationScheduledArrivalTime
            state.nextStep = ["Arrive \(UKStation.name(for: destination))", arrival].compactMap { $0 }.joined(separator: " ")
        }
        return state
    }

    // MARK: - Updates

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
