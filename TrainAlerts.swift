import Foundation
import SwiftData
import UserNotifications

// MARK: - Train Alerts
// Notifications about saved trains. Trainy has no server, so an alert is raised when the app
// itself sees a change: while it is open, or when iOS wakes it for a background refresh.
// Reminders (before a train leaves, before a change, and for Delay Repay) are scheduled ahead,
// so they arrive whether or not the app is running.

@MainActor
@Observable
final class TrainAlerts: NSObject, UNUserNotificationCenterDelegate {

    static let shared = TrainAlerts()
    private override init() {}

    /// The kinds of alert, each with its own switch in Profile → Notifications.
    enum Kind: String {
        case delays = "alerts.delays"
        case platforms = "alerts.platforms"
        /// A change of trains: a warning when one is in doubt, and a reminder on the way into it
        case connections = "alerts.connections"
        /// Reminders an hour and five minutes before a train leaves
        case departures = "alerts.departures"
        case delayRepay = "alerts.delayRepay"
        /// Planned works on a saved route in the coming week
        case engineeringWorks = "alerts.engineeringWorks"
        /// Live disruption on the route of a followed train
        case disruptions = "alerts.disruptions"

        /// On until the user turns it off. Nothing is sent without notification permission.
        var isOn: Bool {
            UserDefaults.standard.object(forKey: rawValue) as? Bool ?? true
        }
    }

    /// What iOS last said about permission. Call `refreshStatus()` to bring it up to date.
    private(set) var status: UNAuthorizationStatus = .notDetermined

    var isAllowed: Bool {
        status == .authorized || status == .provisional
    }

    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    /// The delay each train was last alerted at, so a delay that creeps up a minute at a
    /// time is reported in steps rather than every minute.
    @ObservationIgnored private var alertedDelay: [String: Int] = [:]
    private static let delayStep = 5

    // MARK: - Permission

    func refreshStatus() async {
        let current = await center.notificationSettings().authorizationStatus
        // Checked on every sync: only tell the views when it has really changed
        if current != status { status = current }
    }

    /// Shows the system permission prompt, the first time it is called.
    func requestPermission() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await refreshStatus()
    }

    private func canSend(_ kind: Kind) async -> Bool {
        guard kind.isOn else { return false }
        await refreshStatus()
        return isAllowed
    }

    // MARK: - Live Changes

    /// Compares a train before and after a refresh and alerts the user to what changed.
    func trainChanged(from old: DarwinServiceAdapter, to new: DarwinServiceAdapter) {
        // A Trainy server that is following the train sends these itself, app open or not
        guard new.hasArrived != true, !TrainyServer.shared.isWatching else { return }

        let key = new.journeyKey
        let title = Self.journeyName(new)

        if new.isCancelledService {
            if !old.isCancelledService {
                send(.delays, id: "\(key).delay", title: title, body: "This train has been cancelled.")
            }
            return
        }

        if let body = delayChange(from: old, to: new, key: key) {
            send(.delays, id: "\(key).delay", title: title, body: body)
        }
        if let body = platformChange(from: old, to: new) {
            send(.platforms, id: "\(key).platform", title: title, body: body)
        }
    }

    private func delayChange(from old: DarwinServiceAdapter, to new: DarwinServiceAdapter, key: String) -> String? {
        if new.hasUnknownDelay == true {
            return old.hasUnknownDelay == true ? nil : "Delayed. No new time has been given yet."
        }

        let last = alertedDelay[key] ?? old.delayMinutes
        guard abs(new.delayMinutes - last) >= Self.delayStep else {
            alertedDelay[key] = last
            return nil
        }
        alertedDelay[key] = new.delayMinutes

        guard new.delayMinutes > 0 else { return "Back on time." }

        let late = "Running \(new.delayMinutes) min late."
        if new.departureDelayMinutes > 0, let departure = new.expectedDepartureDate, departure > Date() {
            return "\(late) Now expected to leave at \(new.realtimeDeparture)."
        }
        if let arrival = new.userSearchDestinationArrivalTime {
            return "\(late) Now expected to arrive at \(arrival)."
        }
        return late
    }

    /// An alert when a live feed first gives the platform, and whenever it changes after that.
    /// A platform that is only the timetable's plan is not alerted: it can still change.
    private func platformChange(from old: DarwinServiceAdapter, to new: DarwinServiceAdapter) -> String? {
        guard new.hasConfirmedPlatform else { return nil }

        // A platform is only worth an alert while the train can still be caught
        if let departure = new.expectedDepartureDate, departure < Date() { return nil }

        if old.hasConfirmedPlatform {
            guard new.platform != old.platform else { return nil }
            return "Platform changed to \(new.platform) (was \(old.platform))."
        }
        if Self.isKnown(old.platform), old.platform != new.platform {
            return "Platform \(new.platform) confirmed. The timetable said \(old.platform)."
        }
        return "Platform \(new.platform) confirmed."
    }

    /// Tells the user that a delay has put a change of trains in doubt. Raised by the app
    /// itself even when a Trainy server sends the other alerts: the server follows trains
    /// one by one and does not know which belong to the same journey.
    func connectionChanged(_ connection: JourneyConnection) {
        let next = connection.departing
        let destination = Self.stationName(next.userSearchDestinationCRS ?? next.destinationCRS)
        let train = "the \(next.scheduledDeparture) to \(destination)"

        let body: String
        switch connection.state {
        case .missed:
            let arrival = connection.arriving.userSearchDestinationArrivalTime.map { " Your train is now due in at \($0)." } ?? ""
            body = "You are likely to miss \(train).\(arrival)"
        case .tight:
            guard let minutes = connection.minutes, connection.arriving.hasUnknownDelay != true else {
                body = "Your train is delayed with no new time yet, so \(train) may be missed."
                break
            }
            body = "Only \(minutes) min to catch \(train)."
        case .comfortable, .broken:
            // A cancellation has an alert of its own
            return
        }

        send(.connections, id: "\(next.journeyKey).connection", title: connection.title, body: body)
    }

    private static func isKnown(_ platform: String) -> Bool {
        DarwinServiceAdapter.isKnownPlatform(platform)
    }

    private func send(_ kind: Kind, id: String, title: String, body: String) {
        Task {
            guard await canSend(kind) else { return }
            // Reusing the id replaces the train's earlier alert of the same kind
            let request = UNNotificationRequest(identifier: id, content: Self.content(title: title, body: body), trigger: nil)
            try? await center.add(request)
        }
    }

    // MARK: - Delay Repay Reminders

    private static let reminderPrefix = "delayrepay."

    /// iOS keeps at most 64 scheduled notifications for an app
    private static let reminderLimit = 40

    /// Makes the scheduled reminders match the claims still open: one the morning after the
    /// journey, and one three days before the claim window closes.
    func refreshDelayRepayReminders(in context: ModelContext) async {
        // Every train, so a journey of several is whole: it has one claim, not one a train
        let trains = (try? context.fetch(FetchDescriptor<SavedTrain>())) ?? []
        let reminders = trains.travelItems(past: true)
            .flatMap(Self.reminders(for:))
            .sorted { $0.date < $1.date }
            .prefix(Self.reminderLimit)

        var wanted: [String: (date: Date, content: UNMutableNotificationContent)] = [:]
        if await canSend(.delayRepay) {
            for reminder in reminders {
                wanted[reminder.id] = (reminder.date, Self.content(title: "Delay Repay", body: reminder.body))
            }
        }
        await schedule(wanted, prefix: Self.reminderPrefix)
    }

    /// Makes the notifications scheduled under `prefix` match `wanted`: drops the ones no
    /// longer wanted, and sets again any whose words or time have changed.
    private func schedule(_ wanted: [String: (date: Date, content: UNMutableNotificationContent)], prefix: String) async {
        let scheduled = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: scheduled.map(\.identifier).filter { wanted[$0] == nil })

        let calendar = Calendar.current
        for (id, reminder) in wanted {
            let when = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            let isSet = scheduled.contains { request in
                request.identifier == id
                    && request.content.body == reminder.content.body
                    && (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents == when
            }
            guard !isSet else { continue }
            // Adding under the same identifier replaces the one already waiting
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: id, content: reminder.content, trigger: trigger))
        }
    }

    /// The reminders still to come for a past train or journey with an open claim.
    private static func reminders(for item: TravelItem) -> [(id: String, date: Date, body: String)] {
        item.claims.flatMap { train, claim -> [(id: String, date: Date, body: String)] in
            guard claim.isOpen, let service = train.service else { return [] }

            let calendar = Calendar.current
            let key = reminderPrefix + service.journeyKey

            // A journey of several trains is named by where it started and ended
            var journey = journeyName(service)
            var whatHappened = claim.isCancelled
                ? "Your \(journey) was cancelled. You may be able to claim from \(claim.brand.shortName)."
                : "Your \(journey) was \(claim.delayMinutes) minutes late. You can claim from \(claim.brand.shortName)."
            if claim.isJourney, case .journey(let saved) = item {
                journey = "journey from \(saved.title)"
                whatHappened = claim.isCancelled
                    ? "A train on your \(journey) was cancelled. You may be able to claim from \(claim.brand.shortName)."
                    : "Your \(journey) ended \(claim.delayMinutes) minutes late. You can claim from \(claim.brand.shortName)."
            }

            let nextMorning = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: item.finishedAt))
                .flatMap { calendar.date(bySettingHour: 10, minute: 0, second: 0, of: $0) }
            let lastChance = calendar.date(byAdding: .day, value: -3, to: claim.deadline)

            let reminders = [
                nextMorning.map { (id: "\(key).next", date: $0, body: whatHappened) },
                lastChance.map { (id: "\(key).last", date: $0, body: "3 days left to claim for your \(journey).") }
            ]
            return reminders.compactMap { $0 }.filter { $0.date > Date() }
        }
    }

    // MARK: - Approaching a Change

    private static let approachPrefix = "approach."

    /// How long before the train gets in the reminder arrives
    private static let approachLead: TimeInterval = 5 * 60

    /// Schedules a reminder for a few minutes before each change of trains still to come:
    /// which train is next, where it leaves from and how long there is. Set ahead, so it
    /// arrives whether or not the app is running, with the times as they stood at the last sync.
    func refreshApproachReminders(in context: ModelContext) async {
        let trains = (try? context.fetch(FetchDescriptor<SavedTrain>())) ?? []

        var wanted: [String: (date: Date, content: UNMutableNotificationContent)] = [:]
        if await canSend(.connections) {
            for connection in trains.connections.values {
                guard connection.state != .broken, connection.arriving.hasArrived != true,
                      let arrival = connection.arriving.expectedArrivalDate else { continue }

                let date = arrival.addingTimeInterval(-Self.approachLead)
                guard date > Date() else { continue }

                wanted[Self.approachPrefix + connection.departing.journeyKey] = (
                    date,
                    Self.content(title: connection.title, body: Self.approachBody(connection))
                )
            }
        }
        await schedule(wanted, prefix: Self.approachPrefix)
    }

    private static func approachBody(_ connection: JourneyConnection) -> String {
        let arriving = connection.arriving
        let next = connection.departing
        let station = stationName(arriving.userSearchDestinationCRS ?? arriving.destinationCRS)
        let train = "the \(next.realtimeDeparture) to \(stationName(next.userSearchDestinationCRS ?? next.destinationCRS))"

        if connection.state == .missed {
            return "About 5 minutes to \(station). You are likely to miss \(train). Open Trainy for later trains."
        }

        // Named when the next train goes from somewhere else: across London, say
        let from = next.userSearchOriginCRS ?? next.originCRS
        let elsewhere = from == (arriving.userSearchDestinationCRS ?? arriving.destinationCRS) ? "" : " at \(stationName(from))"

        var body = "About 5 minutes to \(station). Next is \(train)"
        body += isKnown(next.platform) ? ", from platform \(next.platform)\(elsewhere)." : "\(elsewhere)."
        if let minutes = connection.minutes {
            body += " You have \(minutes) min to change."
        }
        return body
    }

    // MARK: - Before Departure

    private static let departurePrefix = "departure."

    /// How long before the train leaves each reminder arrives, in minutes
    private static let departureLeads = [60, 5]

    /// Leaves room under iOS's 64 for the Delay Repay and change reminders
    private static let departureLimit = 16

    /// Schedules a reminder an hour, and another five minutes, before each saved train leaves:
    /// its time and platform as they stood at the last sync. Set ahead, so they arrive whether or
    /// not the app is running, and set again on every sync, so a delay moves them. A Trainy
    /// server that is following the trains sends these itself from live times, so none are set then.
    func refreshDepartureReminders(in context: ModelContext) async {
        let upcoming = FetchDescriptor<SavedTrain>(predicate: #Predicate { !$0.isPast })
        let trains = (try? context.fetch(upcoming)) ?? []

        var reminders: [(id: String, date: Date, content: UNMutableNotificationContent)] = []
        if !TrainyServer.shared.isWatching, await canSend(.departures) {
            let now = Date()
            for saved in trains where saved.remindsBeforeDeparture {
                guard let train = saved.service, !train.isCancelledService, train.hasArrived != true,
                      let departure = train.expectedDepartureDate else { continue }

                for lead in Self.departureLeads {
                    let date = departure.addingTimeInterval(-TimeInterval(lead * 60))
                    guard date > now else { continue }
                    reminders.append((
                        "\(Self.departurePrefix)\(train.journeyKey).\(lead)",
                        date,
                        Self.content(title: Self.journeyName(train), body: Self.departureBody(train, minutes: lead))
                    ))
                }
            }
        }

        var wanted: [String: (date: Date, content: UNMutableNotificationContent)] = [:]
        for reminder in reminders.sorted(by: { $0.date < $1.date }).prefix(Self.departureLimit) {
            wanted[reminder.id] = (reminder.date, reminder.content)
        }
        await schedule(wanted, prefix: Self.departurePrefix)
    }

    /// "Leaves in 1 hour, at 17:52 (10 min late), from platform 4." Worded the same by the server.
    private static func departureBody(_ train: DarwinServiceAdapter, minutes: Int) -> String {
        let when = minutes >= 60 ? "1 hour" : "\(minutes) minutes"
        if train.hasUnknownDelay == true {
            return "Due to leave in \(when), but delayed with no new time yet."
        }

        var body = "Leaves in \(when), at \(train.realtimeDeparture)"
        if train.departureDelayMinutes > 0 {
            body += " (\(train.departureDelayMinutes) min late)"
        }
        body += train.hasConfirmedPlatform ? ", from platform \(train.platform)." : ". Platform not confirmed yet."
        return body
    }

    // MARK: - Live Disruptions

    private static let disruptionsNotifiedKey = "disruptions.notified"

    /// Tells the user once about a disruption on their train's route, the first time it is
    /// seen for that train.
    func disruptionFound(_ disruption: LiveDisruption, on train: DarwinServiceAdapter) {
        let key = "\(disruption.id)|\(train.journeyKey)"
        let now = Date().timeIntervalSince1970
        let defaults = UserDefaults.standard
        // A day is longer than any one train is followed for
        var notified = (defaults.dictionary(forKey: Self.disruptionsNotifiedKey) as? [String: Double] ?? [:])
            .filter { now - $0.value < 24 * 3600 }
        guard notified[key] == nil else { return }
        notified[key] = now
        defaults.set(notified, forKey: Self.disruptionsNotifiedKey)

        send(.disruptions, id: "disruption.\(disruption.id).\(train.id)",
             title: "Disruption · \(Self.journeyName(train))", body: disruption.summary)
    }

    // MARK: - Engineering Works

    private static let worksPrefix = "works."
    private static let worksLimit = 8
    /// When each work's notification went, or is set to go, by the work's id: one per work, ever
    private static let worksNotifiedKey = "works.notified"

    /// One notification per planned work on a saved route, at six in the evening two days
    /// before it starts, or at once for a work found later than that. `alerts` soonest first.
    func refreshEngineeringWorksAlerts(_ alerts: [(work: EngineeringWork, route: String)]) async {
        let now = Date()
        let defaults = UserDefaults.standard
        // Long enough to outlast any work in the feed's week ahead
        var notified = (defaults.dictionary(forKey: Self.worksNotifiedKey) as? [String: Double] ?? [:])
            .filter { now.timeIntervalSince1970 - $0.value < 60 * 24 * 3600 }

        var wanted: [String: (date: Date, content: UNMutableNotificationContent)] = [:]
        if await canSend(.engineeringWorks) {
            var count = 0
            for (work, route) in alerts where count < Self.worksLimit {
                // Already sent
                if let sent = notified[work.id], sent <= now.timeIntervalSince1970 { continue }

                count += 1
                let id = Self.worksPrefix + work.id
                let content = Self.content(title: "Engineering works · \(route)", body: work.summary)
                let due = Self.worksReminderDate(for: work)
                if due <= now.addingTimeInterval(60) {
                    try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
                    notified[work.id] = now.timeIntervalSince1970
                } else {
                    wanted[id] = (due, content)
                    notified[work.id] = due.timeIntervalSince1970
                }
            }
        }
        // Those still waiting that are no longer wanted go; when one is wanted again its entry,
        // being in the future, does not count as sent
        await schedule(wanted, prefix: Self.worksPrefix)
        defaults.set(notified, forKey: Self.worksNotifiedKey)
    }

    /// Six in the evening, UK time, two days before the work starts: in time to plan a weekend.
    private static func worksReminderDate(for work: EngineeringWork) -> Date {
        let calendar = SavedRoute.ukCalendar
        guard let day = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: work.start)),
              let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day) else { return work.start }
        return evening
    }

    /// Clears every alert and reminder, delivered or still to come.
    func removeAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        alertedDelay = [:]
    }

    // MARK: - Wording

    /// "20:05 Milton Keynes Central to London Euston"
    private static func journeyName(_ train: DarwinServiceAdapter) -> String {
        let origin = stationName(train.userSearchOriginCRS ?? train.originCRS)
        let destination = stationName(train.userSearchDestinationCRS ?? train.destinationCRS)
        return "\(train.scheduledDeparture) \(origin) to \(destination)"
    }

    private static func stationName(_ crs: String) -> String {
        ukStations.first { $0.crs == crs }?.name ?? crs
    }

    private static func content(title: String, body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        return content
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Alerts are mostly raised while the app is open, so show them then too.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
