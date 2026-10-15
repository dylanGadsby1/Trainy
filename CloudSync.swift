import Foundation
import SwiftData
import CloudKit

// MARK: - iCloud Sync
// Optional. With the iCloud capability and a CloudKit container turned on in Xcode (see README),
// the saved trains, Rail History and saved routes are kept in the user's private iCloud
// database, so every device signed in to the same Apple ID has them. A few preferences follow
// through the same store (SyncedSetting), so CloudKit is the only iCloud service needed.
// Without the capability, everything stays on this device.

@MainActor
enum CloudSync {

    /// The iCloud container the store is kept in. Nil when it is kept on this device only.
    private(set) static var containerIdentifier: String?

    /// True when the store is being kept in iCloud
    static var isOn: Bool { containerIdentifier != nil }

    // MARK: - Store

    /// The app's store. SwiftData keeps it in iCloud when the app has the iCloud capability
    /// with a CloudKit container, and on this device only when it has not. Turning the
    /// capability on in Xcode is all it takes: asking for a container the app is not
    /// entitled to would stop the app at launch, so none is named here.
    static func makeContainer(for schema: Schema) -> ModelContainer {
        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            containerIdentifier = container.configurations.first?.cloudKitContainerIdentifier
            print(isOn ? "☁️ Keeping your trains in iCloud (\(containerIdentifier ?? ""))" : "☁️ iCloud is not set up: keeping your trains on this device")
            return container
        } catch {
            // Not expected, but better a store on this device than none
            print("☁️ Could not open the store with iCloud, so it stays on this device: \(error)")
        }

        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    /// What Profile shows for iCloud sync. Nil when it is not set up.
    static func status() async -> String? {
        guard isOn, let containerIdentifier else { return nil }
        let status = try? await CKContainer(identifier: containerIdentifier).accountStatus()
        switch status {
        case .available: return "On"
        case .noAccount: return "Sign in to iCloud"
        case .restricted: return "Restricted"
        default: return "Unavailable"
        }
    }

    // MARK: - Duplicates

    /// Two devices can each save the same train before either has seen the other's, a commute
    /// train above all, since every device follows it 12 hours ahead. Keeps one of each.
    static func mergeDuplicates(in context: ModelContext) {
        guard isOn else { return }
        merge(in: context)
    }

    /// Of the copies of one thing, the one kept is the one saved first. Every device decides
    /// the same way, so two devices tidying at once can never remove every copy between them:
    /// a copy is only removed while an earlier one exists.
    static func merge(in context: ModelContext) {
        let trains = (try? context.fetch(FetchDescriptor<SavedTrain>())) ?? []
        let routes = (try? context.fetch(FetchDescriptor<SavedRoute>())) ?? []
        var removed = 0

        // A train followed on its own: one per journey key
        let single = Dictionary(grouping: trains.filter { $0.journeyID == nil }) { $0.service?.journeyKey ?? $0.id }
        for copies in single.values where copies.count > 1 {
            let sorted = copies.sorted(by: savedFirst)
            for copy in sorted.dropFirst() {
                absorb(copy, into: sorted[0])
                context.delete(copy)
                removed += 1
            }
        }

        // A journey with a change: the same trains, in the same order, under two journey IDs
        let journeys = Dictionary(grouping: trains.filter { $0.journeyID != nil }) { $0.journeyID ?? "" }
        let sameTrains = Dictionary(grouping: journeys.values) { legs in
            legs.sorted { $0.legIndex < $1.legIndex }.map { $0.service?.journeyKey ?? $0.id }.joined(separator: "|")
        }
        for copies in sameTrains.values where copies.count > 1 {
            let sorted = copies.sorted { first, second in
                let a = first.min(by: savedFirst), b = second.min(by: savedFirst)
                guard let a, let b else { return a != nil }
                return savedFirst(a, b)
            }
            let kept = sorted[0]
            for journey in sorted.dropFirst() {
                for leg in journey {
                    if let match = kept.first(where: { $0.legIndex == leg.legIndex }) {
                        absorb(leg, into: match)
                    }
                    context.delete(leg)
                    removed += 1
                }
            }
        }

        // A saved route: one per origin and destination
        let sameRoute = Dictionary(grouping: routes) { "\($0.originCRS)-\($0.destinationCRS)" }
        for copies in sameRoute.values where copies.count > 1 {
            let sorted = copies.sorted { ($0.addedAt, $0.lastCommuteDay ?? "") < ($1.addedAt, $1.lastCommuteDay ?? "") }
            let kept = sorted[0]
            for copy in sorted.dropFirst() {
                if kept.commuteDays == 0, copy.commuteDays != 0 {
                    kept.commuteDays = copy.commuteDays
                    kept.commuteMinutes = copy.commuteMinutes
                }
                kept.lastCommuteDay = [kept.lastCommuteDay, copy.lastCommuteDay].compactMap { $0 }.max()
                context.delete(copy)
                removed += 1
            }
        }

        if removed > 0 {
            try? context.save()
            print("☁️ Merged \(removed) copies saved on another device")
        }
    }

    private static func savedFirst(_ a: SavedTrain, _ b: SavedTrain) -> Bool {
        (a.addedAt, a.id, a.journeyID ?? "") < (b.addedAt, b.id, b.journeyID ?? "")
    }

    /// Keeps what only the copy being removed knows
    private static func absorb(_ copy: SavedTrain, into kept: SavedTrain) {
        if let claimed = copy.delayRepayClaimedAt, kept.delayRepayClaimedAt.map({ claimed < $0 }) ?? true {
            kept.delayRepayClaimedAt = claimed
        }
        // Another device saw it finish
        if copy.isPast, !kept.isPast {
            kept.isPast = true
            kept.movedToPastAt = copy.movedToPastAt
        }
        if copy.service?.hasArrived == true, kept.service?.hasArrived != true {
            kept.serviceData = copy.serviceData
        }
    }

    // MARK: - Preferences

    /// Kept the same on every device: they are about the user, where the notification
    /// switches and the map style are about one device
    private static let syncedKeys = [
        profileNameKey,
        JourneyOptions.extraChangeMinutesKey,
        JourneyOptions.fewestChangesKey,
        JourneyOptions.avoidTubeKey,
        RecentStationSearches.key,
    ]

    private static var local: UserDefaults { .standard }

    /// Each synced preference as last recorded or taken in, so only a change made on this
    /// device is recorded, never one simply not taken in from another device yet
    private static var lastSeen: [String: Any] = [:]

    /// Records this device's changes to the synced preferences from now on, and takes in
    /// what other devices have set. Later changes from other devices arrive with each sync.
    static func startSyncingPreferences(in container: ModelContainer) {
        guard isOn else { return }

        _ = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: local, queue: .main
        ) { _ in
            MainActor.assumeIsolated { recordPreferences(in: container.mainContext) }
        }

        applyPreferences(in: container.mainContext)
        recordPreferences(in: container.mainContext)
    }

    /// Sets this device's preferences to the latest any device has recorded, keeping one
    /// record a preference.
    static func applyPreferences(in context: ModelContext) {
        guard isOn else { return }
        let settings = (try? context.fetch(FetchDescriptor<SyncedSetting>())) ?? []

        for (key, copies) in Dictionary(grouping: settings, by: \.settingKey) {
            // The newest wins. Each device picks the same one, so one always survives.
            let sorted = copies.sorted { ($0.changedAt, $0.plist.base64EncodedString()) > ($1.changedAt, $1.plist.base64EncodedString()) }
            for copy in sorted.dropFirst() {
                context.delete(copy)
            }
            guard syncedKeys.contains(key), let value = sorted[0].decoded else { continue }
            // Taken in before recording, so setting it here is not mistaken for a change made here
            lastSeen[key] = value
            if !isSame(value, local.object(forKey: key)) {
                local.set(value, forKey: key)
            }
        }
        try? context.save()
    }

    /// Records any synced preference changed on this device since it was last recorded or
    /// taken in from another device.
    private static func recordPreferences(in context: ModelContext) {
        let settings = (try? context.fetch(FetchDescriptor<SyncedSetting>())) ?? []
        var changed = false

        for key in syncedKeys {
            // A preference never set on this device has nothing to say
            guard let value = local.object(forKey: key), !isSame(value, lastSeen[key]),
                  let data = try? PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0) else { continue }
            lastSeen[key] = value
            let newest = settings.filter { $0.settingKey == key }.max { $0.changedAt < $1.changedAt }
            guard !isSame(value, newest?.decoded) else { continue }

            if let newest {
                newest.plist = data
                newest.changedAt = Date()
            } else {
                context.insert(SyncedSetting(settingKey: key, plist: data))
            }
            changed = true
        }
        if changed {
            try? context.save()
        }
    }

    private static func isSame(_ a: Any?, _ b: Any?) -> Bool {
        guard let a = a as? NSObject else { return b == nil }
        return a.isEqual(b)
    }
}

// MARK: - Synced Setting

/// One preference as recorded for the user's other devices (CloudSync)
@Model
final class SyncedSetting {
    /// The UserDefaults key
    var settingKey: String = ""
    /// The value as a property list
    var plist: Data = Data()
    var changedAt: Date = Date()

    init(settingKey: String, plist: Data) {
        self.settingKey = settingKey
        self.plist = plist
        self.changedAt = Date()
    }

    var decoded: Any? {
        try? PropertyListSerialization.propertyList(from: plist, format: nil)
    }
}
