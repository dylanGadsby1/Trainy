import Foundation
import SwiftData
import UserNotifications

// MARK: - Train Alerts
// Notifications about saved trains. Trainy has no server, so an alert is raised when the app
// itself sees a change: while it is open, or when iOS wakes it for a background refresh.
// Delay Repay reminders are scheduled ahead, so they arrive whether or not the app is running.

@MainActor
@Observable
final class TrainAlerts: NSObject, UNUserNotificationCenterDelegate {

    static let shared = TrainAlerts()
    private override init() {}

    /// The kinds of alert, each with its own switch in Profile → Notifications.
    enum Kind: String {
        case delays = "alerts.delays"
        case platforms = "alerts.platforms"
        case delayRepay = "alerts.delayRepay"

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

    private func platformChange(from old: DarwinServiceAdapter, to new: DarwinServiceAdapter) -> String? {
        guard new.platform != old.platform, Self.isKnown(new.platform) else { return nil }

        // A platform is only worth an alert while the train can still be caught
        if let departure = new.expectedDepartureDate, departure < Date() { return nil }

        return Self.isKnown(old.platform)
            ? "Platform changed to \(new.platform) (was \(old.platform))."
            : "Leaves from platform \(new.platform)."
    }

    private static func isKnown(_ platform: String) -> Bool {
        !platform.isEmpty && platform != "TBC"
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
        let pastTrains = (try? context.fetch(FetchDescriptor<SavedTrain>(predicate: #Predicate { $0.isPast }))) ?? []
        let reminders = pastTrains
            .flatMap(Self.reminders(for:))
            .sorted { $0.date < $1.date }
            .prefix(Self.reminderLimit)

        var wanted: [String: (date: Date, content: UNMutableNotificationContent)] = [:]
        if await canSend(.delayRepay) {
            for reminder in reminders {
                wanted[reminder.id] = (reminder.date, Self.content(title: "Delay Repay", body: reminder.body))
            }
        }

        let scheduled = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(Self.reminderPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: scheduled.map(\.identifier).filter { wanted[$0] == nil })

        for (id, reminder) in wanted where !scheduled.contains(where: { $0.identifier == id && $0.content.body == reminder.content.body }) {
            let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: id, content: reminder.content, trigger: trigger))
        }
    }

    /// The reminders still to come for a past journey with an open claim.
    private static func reminders(for train: SavedTrain) -> [(id: String, date: Date, body: String)] {
        guard let claim = train.delayRepay, claim.isOpen, let service = train.service else { return [] }

        let calendar = Calendar.current
        let key = reminderPrefix + service.journeyKey
        let journey = journeyName(service)
        let finished = train.movedToPastAt ?? train.addedAt

        let whatHappened = claim.isCancelled
            ? "Your \(journey) was cancelled. You may be able to claim from \(claim.brand.shortName)."
            : "Your \(journey) was \(claim.delayMinutes) minutes late. You can claim from \(claim.brand.shortName)."
        let nextMorning = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: finished))
            .flatMap { calendar.date(bySettingHour: 10, minute: 0, second: 0, of: $0) }
        let lastChance = calendar.date(byAdding: .day, value: -3, to: claim.deadline)

        let reminders = [
            nextMorning.map { (id: "\(key).next", date: $0, body: whatHappened) },
            lastChance.map { (id: "\(key).last", date: $0, body: "3 days left to claim for your \(journey).") }
        ]
        return reminders.compactMap { $0 }.filter { $0.date > Date() }
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
