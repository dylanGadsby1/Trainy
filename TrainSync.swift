import Foundation
import SwiftData
import BackgroundTasks
import WidgetKit

// MARK: - Train Sync
// Keeps every saved train up to date and decides which feed it is read from:
//
//   more than ~4 hours before departure   Realtime Trains (timetable; checked every half hour)
//   ~4 hours before → 2 hours after       Darwin (live; checked every minute)
//   after Darwin drops the train          Realtime Trains again, until it is seen arriving
//
// A train saved from the timetable carries a Realtime Trains identity. The first time
// Darwin lists it, it is matched by its journey and switched to its Darwin identity.

@MainActor
final class TrainSync {

    static let shared = TrainSync()
    private init() {}

    private var isSyncing = false

    /// When each train was last read from Realtime Trains, which allows only 100 requests an hour.
    private var lastTimetableCheck: [String: Date] = [:]

    /// The trains whose path along the tracks has been asked for since the app started. Each
    /// is asked for once: the planner is a shared, free service.
    private var routeLinesAsked: Set<String> = []

    // MARK: - Sync

    /// Refreshes the saved trains, hands timetable trains over to Darwin, and moves
    /// finished trains to Rail History.
    func sync(in context: ModelContext) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        // First, so a commute train added now is refreshed with the rest
        await CommuteMode.shared.followDueTrains(in: context)

        let savedTrains = (try? context.fetch(FetchDescriptor<SavedTrain>())) ?? []
        // How every change of trains stood before the refresh, to see which it has put in doubt
        let connectionsBefore = savedTrains.connectionStates

        for saved in savedTrains {
            guard let train = saved.service, needsRefresh(saved, train),
                  let updated = await refreshed(train),
                  updated != train,
                  // The train may have been removed while the request was in flight
                  saved.modelContext != nil, !saved.isDeleted,
                  let data = try? JSONEncoder().encode(updated) else { continue }

            if updated.dataSource == .darwin && train.dataSource == .rtt {
                print("🔄 \(train.scheduledDeparture) \(train.originCRS)→\(train.destinationCRS) is now live on Darwin: \(train.id) became \(updated.id)")
            }

            saved.serviceData = data
            saved.id = updated.id
            LiveActivityManager.shared.updateTracking(with: updated)
            if !saved.isPast {
                TrainAlerts.shared.trainChanged(from: train, to: updated)
            }
        }

        for (key, connection) in savedTrains.connections
        where connection.isAhead() && connection.state != connectionsBefore[key] {
            TrainAlerts.shared.connectionChanged(connection)
        }

        await fetchRouteLines(for: savedTrains)

        archiveFinishedTrains(savedTrains)
        try? context.save()
        // A journey's Live Activity moves on to its next train, and ends with the journey
        LiveActivityManager.shared.updateJourney(with: savedTrains)
        await TrainAlerts.shared.refreshApproachReminders(in: context)
        await TrainAlerts.shared.refreshDelayRepayReminders(in: context)
        await TrainyServer.shared.sync(in: context)
        // After the server, which sends these itself once it is following the trains
        await TrainAlerts.shared.refreshDepartureReminders(in: context)
        WidgetSync.update(in: context)
    }

    /// Gets the path along the tracks for trains still to run that have none, a few at a
    /// time, so the map can draw each journey where it really goes.
    private func fetchRouteLines(for savedTrains: [SavedTrain]) async {
        var asked = 0
        for saved in savedTrains where !saved.isPast {
            guard asked < 4, saved.modelContext != nil, !saved.isDeleted,
                  let train = saved.service, train.routeLine == nil, !train.isCancelledService,
                  routeLinesAsked.insert(train.journeyKey).inserted else { continue }
            asked += 1

            guard let line = await JourneyPlanner.shared.routeLine(for: train),
                  // The train may have been removed, or refreshed, while the request was in flight
                  saved.modelContext != nil, !saved.isDeleted, var current = saved.service else { continue }
            current.routeLine = line
            if let data = try? JSONEncoder().encode(current) {
                saved.serviceData = data
            }
        }
    }

    /// The latest version of `train` from whichever feed can see it, or nil if neither can right now.
    func refreshed(_ train: DarwinServiceAdapter) async -> DarwinServiceAdapter? {
        if let live = await DarwinService.shared.refreshed(train) {
            return live
        }

        // Darwin is not listing it: too early, too late, or the request failed
        let now = Date()
        let key = train.rttIdentity ?? train.id
        if let last = lastTimetableCheck[key], now.timeIntervalSince(last) < timetableInterval(for: train, now: now) {
            return nil
        }
        lastTimetableCheck[key] = now

        var train = train
        if train.rttIdentity == nil {
            train.rttIdentity = await RTTService.shared.identity(for: train)
        }
        // Even when the read fails, hand back the identity so it is not looked up again
        return await RTTService.shared.refreshed(train) ?? train
    }

    // MARK: - Rules

    private func needsRefresh(_ saved: SavedTrain, _ train: DarwinServiceAdapter) -> Bool {
        guard saved.isPast else { return true }

        // A train moves to Rail History at its expected arrival. Keep following it for a
        // while after that, so the history records when it really arrived.
        guard train.hasArrived != true, !train.isCancelledService,
              let finished = saved.movedToPastAt else { return false }
        return Date().timeIntervalSince(finished) < 3 * 3600
    }

    /// The timetable rarely changes hours ahead; a running train needs a closer watch.
    private func timetableInterval(for train: DarwinServiceAdapter, now: Date) -> TimeInterval {
        guard let departure = train.scheduledDepartureDate, departure > now else { return 5 * 60 }
        return 30 * 60
    }

    private func archiveFinishedTrains(_ savedTrains: [SavedTrain]) {
        let now = Date()

        for saved in savedTrains where !saved.isPast {
            guard let train = saved.service else { continue }

            // A cancelled train stays in My Trains until it would have left, so the user
            // sees what happened and can switch to another train. Otherwise a train moves
            // to Rail History once its real (with-delay) arrival time has passed, or four
            // hours after it was due to leave when no arrival time is known.
            let finishedAt: Date?
            if train.isCancelledService {
                finishedAt = now >= (train.scheduledDepartureDate ?? now) ? now : nil
            } else if let arrival = train.expectedArrivalDate {
                finishedAt = now >= arrival ? arrival : nil
            } else {
                let departure = train.scheduledDepartureDate ?? saved.addedAt
                finishedAt = now.timeIntervalSince(departure) > 4 * 3600 ? now : nil
            }

            if let finishedAt = finishedAt {
                saved.isPast = true
                saved.movedToPastAt = finishedAt
                LiveActivityManager.shared.endTracking(for: train)
            }
        }
    }
}

// MARK: - Widgets

/// Gives the Home Screen and Lock Screen widgets the saved trains still to come, and asks
/// them to redraw when something they show has changed.
enum WidgetSync {

    /// More than a medium widget shows, so it has the next ones ready as each train leaves
    private static let limit = 8

    @MainActor
    static func update(in context: ModelContext) {
        let upcoming = FetchDescriptor<SavedTrain>(predicate: #Predicate { !$0.isPast })
        let saved = (try? context.fetch(upcoming)) ?? []

        // The last train of each journey with a change: every train before it ends at a change
        var lastLeg: [String: Int] = [:]
        for item in saved {
            if let journey = item.journeyID { lastLeg[journey] = max(lastLeg[journey] ?? 0, item.legIndex) }
        }

        let trains = saved.compactMap { item -> TrainyWidgetData.Train? in
            guard let train = item.service,
                  let departs = train.expectedDepartureDate ?? train.scheduledDepartureDate else { return nil }
            let origin = train.userSearchOriginCRS ?? train.originCRS
            let destination = train.userSearchDestinationCRS ?? train.destinationCRS
            let changes = item.journeyID.map { item.legIndex < (lastLeg[$0] ?? 0) } ?? false

            return TrainyWidgetData.Train(
                id: train.journeyKey,
                originCRS: origin,
                originName: stationName(origin),
                destinationCRS: destination,
                destinationName: stationName(destination),
                scheduledDeparture: train.scheduledDeparture,
                expectedDeparture: train.realtimeDeparture,
                departs: departs,
                arrives: train.expectedArrivalDate,
                expectedArrival: train.userSearchDestinationArrivalTime,
                platform: DarwinServiceAdapter.isKnownPlatform(train.platform) ? train.platform : nil,
                platformConfirmed: train.hasConfirmedPlatform,
                delayMinutes: train.delayMinutes,
                isCancelled: train.isCancelledService,
                hasUnknownDelay: train.hasUnknownDelay == true,
                isScheduled: train.isAwaitingLiveData == true,
                operatorName: OperatorBrand.from(code: train.atocCode)?.shortName ?? train.atocName,
                changeAt: changes ? stationName(destination) : nil
            )
        }

        let soonest = Array(trains.sorted { $0.departs < $1.departs }.prefix(limit))
        if TrainyWidgetData.save(soonest) {
            WidgetCenter.shared.reloadTimelines(ofKind: TrainyWidgetData.kind)
        }
    }

    private static func stationName(_ crs: String) -> String {
        ukStations.first { $0.crs == crs }?.name ?? crs
    }
}

// MARK: - Background Refresh

/// Lets iOS wake the app now and then to refresh the saved trains, so alerts and the Live
/// Activity keep up while the app is closed. iOS decides when, so this is best effort.
enum BackgroundRefresh {

    /// Also listed under BGTaskSchedulerPermittedIdentifiers in Info.plist
    static let identifier = "com.dylangadsby.Trainy.refresh"

    /// Asks for the next wake-up, if there is still a train to follow or a commute to follow one for.
    @MainActor
    static func schedule(in container: ModelContainer) {
        let upcoming = FetchDescriptor<SavedTrain>(predicate: #Predicate { !$0.isPast })
        let commutes = FetchDescriptor<SavedRoute>(predicate: #Predicate { $0.commuteDays != 0 })
        let context = container.mainContext
        guard ((try? context.fetchCount(upcoming)) ?? 0) + ((try? context.fetchCount(commutes)) ?? 0) > 0 else { return }

        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func run(in container: ModelContainer) async {
        schedule(in: container)
        await TrainSync.shared.sync(in: container.mainContext)
    }
}
