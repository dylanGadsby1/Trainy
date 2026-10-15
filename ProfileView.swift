import SwiftUI
import SwiftData
import StoreKit
import ActivityKit
import UserNotifications

/// Also synced through iCloud (CloudSync)
let profileNameKey = "profile.name"

// MARK: - Profile View

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @Query(sort: \SavedTrain.addedAt) private var trains: [SavedTrain]
    @Query(filter: #Predicate<SavedRoute> { $0.commuteDays != 0 }) private var commutes: [SavedRoute]

    @AppStorage(profileNameKey) private var name = ""
    @AppStorage(TrainAlerts.Kind.delays.rawValue) private var delayAlerts = true
    @AppStorage(TrainAlerts.Kind.platforms.rawValue) private var platformAlerts = true
    @AppStorage(TrainAlerts.Kind.delayRepay.rawValue) private var delayRepayReminders = true
    @AppStorage(TrainAlerts.Kind.connections.rawValue) private var connectionAlerts = true
    @AppStorage(TrainAlerts.Kind.departures.rawValue) private var departureReminders = true

    private var notificationsAreOn: Bool {
        TrainAlerts.shared.isAllowed && (delayAlerts || platformAlerts || connectionAlerts || departureReminders || delayRepayReminders)
    }

    private var commuteValue: String {
        switch commutes.count {
        case 0: return "Off"
        case 1: return commutes[0].commuteSummary ?? "On"
        default: return "\(commutes.count) routes"
        }
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    var body: some View {
        let stats = TravelStats(trains)

        NavigationStack {
            List {
                Section {
                    header
                }
                .listRowBackground(Color.clear)

                Section {
                    HStack {
                        StatTile(value: stats.journeys.formatted(), label: "Journeys")
                        Divider()
                        StatTile(value: stats.miles.formatted(.number.notation(.compactName)), label: "Miles")
                        Divider()
                        StatTile(value: stats.onTimeText, label: "On Time")
                    }
                    .padding(.vertical, 6)

                    NavigationLink("All Stats") {
                        RailStatsView()
                    }
                } header: {
                    Text("Your Travel")
                } footer: {
                    Text("From your Rail History. Miles are measured in a straight line between stations.")
                }
                .listRowBackground(Color.card)

                Section("Settings") {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        SettingsRow("Notifications", systemImage: "bell.badge.fill", value: notificationsAreOn ? "On" : "Off")
                    }

                    NavigationLink {
                        CommuteSettingsView()
                    } label: {
                        SettingsRow("Commute", systemImage: "briefcase.fill", value: commuteValue)
                    }

                    NavigationLink {
                        DelayRepayClaimsView()
                    } label: {
                        SettingsRow("Delay Repay", systemImage: "sterlingsign", value: stats.openClaims > 0 ? "\(stats.openClaims) to claim" : "")
                    }

                    NavigationLink {
                        PrivacyView()
                    } label: {
                        SettingsRow("Privacy", systemImage: "hand.raised.fill")
                    }
                }
                .listRowBackground(Color.card)

                Section("About") {
                    Button(action: rate) {
                        SettingsRow("Rate Trainy", systemImage: "star.fill")
                    }
                    .tint(.primary)

                    NavigationLink {
                        AboutView()
                    } label: {
                        SettingsRow("About", systemImage: "info", value: AppInfo.version)
                    }
                }
                .listRowBackground(Color.card)
            }
            .appListSurface()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await TrainAlerts.shared.refreshStatus()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.brandFill)
                if initials.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: 36, weight: .semibold))
                } else {
                    Text(initials)
                        .font(.system(size: 32, weight: .bold))
                }
            }
            .foregroundStyle(Color.onBrand)
            .accessibilityHidden(true)
            .frame(width: 86, height: 86)

            TextField("Add Your Name", text: $name)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)

            Text(trains.first.map { "Tracking trains since \($0.addedAt.formatted(.dateTime.month(.wide).year()))" } ?? "No trains tracked yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// A rating the user asks to give goes to the App Store page; until Trainy has one,
    /// the system prompt is the only place to leave it.
    private func rate() {
        if let id = AppInfo.appStoreID, let url = URL(string: "https://apps.apple.com/app/id\(id)?action=write-review") {
            openURL(url)
        } else {
            requestReview()
        }
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A row as in the Settings app: an icon on a tile, a title, and the current value. The tiles
/// are all ink, so no colour here competes with the ones that mean a train's status.
private struct SettingsRow: View {
    let title: String
    let systemImage: String
    let value: String

    init(_ title: String, systemImage: String, value: String = "") {
        self.title = title
        self.systemImage = systemImage
        self.value = value
    }

    var body: some View {
        LabeledContent {
            Text(value)
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.onBrand)
                    .frame(width: 29, height: 29)
                    .background(Color.brandFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
    }
}

// MARK: - Notifications

struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(TrainAlerts.Kind.delays.rawValue) private var delayAlerts = true
    @AppStorage(TrainAlerts.Kind.platforms.rawValue) private var platformAlerts = true
    @AppStorage(TrainAlerts.Kind.delayRepay.rawValue) private var delayRepayReminders = true
    @AppStorage(TrainAlerts.Kind.connections.rawValue) private var connectionAlerts = true
    @AppStorage(TrainAlerts.Kind.departures.rawValue) private var departureReminders = true

    private var alerts: TrainAlerts { .shared }

    var body: some View {
        Form {
            permissionSection

            Section {
                Toggle("Delays and Cancellations", isOn: $delayAlerts)
                Toggle("Platforms", isOn: $platformAlerts)
            } header: {
                Text("Your Trains")
            } footer: {
                Text("A platform alert comes when the platform is confirmed and whenever it changes. "
                     + (TrainyServer.baseURL == nil
                        ? "Sent when Trainy sees a change, while it is open or when iOS refreshes it in the background. Alerts can arrive a few minutes after the change."
                        : "Sent by Trainy's server within about a minute of a change, whether or not the app is open."))
            }
            .disabled(!alerts.isAllowed)
            .listRowBackground(Color.card)

            Section {
                Toggle("An Hour and 5 Minutes Before", isOn: $departureReminders)
            } header: {
                Text("Before You Leave")
            } footer: {
                Text("A reminder an hour before your train leaves and another five minutes before, with its time and platform. On a journey with a change, only for the first train."
                     + (TrainyServer.baseURL == nil ? " They go by the times Trainy last saw." : ""))
            }
            .disabled(!alerts.isAllowed)
            .listRowBackground(Color.card)

            Section {
                Toggle("Changes of Train", isOn: $connectionAlerts)
            } header: {
                Text("Journeys with a Change")
            } footer: {
                Text("A warning when a delay puts a change at risk, and a reminder about five minutes before you arrive for one: your next train, its platform and how long you have. Both go by the times Trainy last saw.")
            }
            .disabled(!alerts.isAllowed)
            .listRowBackground(Color.card)

            Section {
                Toggle("Claim Reminders", isOn: $delayRepayReminders)
            } header: {
                Text("Delay Repay")
            } footer: {
                Text("A reminder the morning after a late or cancelled train, and again three days before the claim window closes.")
            }
            .disabled(!alerts.isAllowed)
            .listRowBackground(Color.card)
        }
        .appListSurface()
        // Switches are the brand colour when on: green is kept for a train that is on time
        .tint(Color.brandFill)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        // Permission can change in Settings while the app is in the background
        .task(id: scenePhase) {
            await alerts.refreshStatus()
        }
        .onChange(of: delayRepayReminders) {
            Task { await alerts.refreshDelayRepayReminders(in: modelContext) }
        }
        .onChange(of: connectionAlerts) {
            Task { await alerts.refreshApproachReminders(in: modelContext) }
        }
        .onChange(of: departureReminders) {
            Task { await alerts.refreshDepartureReminders(in: modelContext) }
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        switch alerts.status {
        case .notDetermined:
            Section {
                Button("Allow Notifications") {
                    Task {
                        await alerts.requestPermission()
                        await alerts.refreshDelayRepayReminders(in: modelContext)
                        await alerts.refreshDepartureReminders(in: modelContext)
                    }
                }
            } footer: {
                Text("iOS will ask whether Trainy may send you notifications.")
            }
            .listRowBackground(Color.card)
        case .denied:
            Section {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                }
            } footer: {
                Text("Notifications are turned off for Trainy. Turn them on in Settings to get alerts.")
            }
            .listRowBackground(Color.card)
        default:
            EmptyView()
        }
    }
}

// MARK: - Privacy

struct PrivacyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query private var trains: [SavedTrain]
    @Query private var routes: [SavedRoute]
    @AppStorage(profileNameKey) private var name = ""

    @State private var confirmingErase = false
    @State private var liveActivitiesAreOn = ActivityAuthorizationInfo().areActivitiesEnabled
    @State private var iCloudStatus: String?

    /// Where the data is kept, for the wording below
    private var whereKept: String {
        CloudSync.isOn ? "this iPhone and your iCloud account" : "this iPhone"
    }

    private var notificationStatus: String {
        switch TrainAlerts.shared.status {
        case .notDetermined: return "Not Asked"
        case .denied: return "Off"
        default: return "On"
        }
    }

    var body: some View {
        List {
            Section {
                if CloudSync.isOn {
                    Label("Your trains, Rail History, saved routes and name are kept on this iPhone and in your own iCloud account, so every device signed in to it has them. Only you can see them. Trainy has no accounts, analytics or adverts.", systemImage: "icloud")
                } else {
                    Label("Your trains, Rail History, saved routes and name are kept on this iPhone. Trainy has no accounts, analytics or adverts.", systemImage: "iphone")
                }
                Label("To find and follow trains, Trainy sends the stations and times you look up to National Rail and Realtime Trains. It does not send your name or your history.", systemImage: "network")
                if TrainyServer.baseURL != nil {
                    Label("While notifications are on, Trainy's server holds this iPhone's notification address and the trains you are following, so it can tell you when they change. A train is removed once it has run.", systemImage: "bell.badge")
                }
            } header: {
                Text("Your Data")
            }
            .listRowBackground(Color.card)

            Section {
                LabeledContent("Notifications", value: notificationStatus)
                LabeledContent("Live Activities", value: liveActivitiesAreOn ? "On" : "Off")
                if let iCloudStatus {
                    LabeledContent("iCloud Sync", value: iCloudStatus)
                }
                LabeledContent("Location", value: "Not Used")
                Button("Open Trainy Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            } header: {
                Text("Permissions")
            }
            .listRowBackground(Color.card)

            Section {
                Button("Erase All Trainy Data", role: .destructive) {
                    confirmingErase = true
                }
                .disabled(trains.isEmpty && routes.isEmpty && name.isEmpty)
                .confirmationDialog("Erase all Trainy data?", isPresented: $confirmingErase, titleVisibility: .visible) {
                    Button("Erase Everything", role: .destructive, action: erase)
                } message: {
                    Text(CloudSync.isOn
                         ? "Your saved trains, Rail History, saved routes and name will be removed from this iPhone, your iCloud account and your other devices. This cannot be undone."
                         : "Your saved trains, Rail History, saved routes and name will be removed from this iPhone. This cannot be undone.")
                }
            } footer: {
                Text("Removes your saved trains, Rail History, saved routes and name from \(whereKept)\(CloudSync.isOn ? ", and so from your other devices" : "").")
            }
            .listRowBackground(Color.card)
        }
        .appListSurface()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        // Permissions can change in Settings while the app is in the background
        .task(id: scenePhase) {
            await TrainAlerts.shared.refreshStatus()
            liveActivitiesAreOn = ActivityAuthorizationInfo().areActivitiesEnabled
            iCloudStatus = await CloudSync.status()
        }
    }

    private func erase() {
        for train in trains {
            modelContext.delete(train)
        }
        for route in routes {
            modelContext.delete(route)
        }
        try? modelContext.save()
        name = ""

        LiveActivityManager.shared.endTracking()
        TrainAlerts.shared.removeAll()
        Task { await TrainyServer.shared.forget() }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - About

private enum AppInfo {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"

    /// Trainy's numeric App Store id, once it is listed
    static let appStoreID: String? = nil
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    // The app icon itself cannot be loaded by name, so the asset catalog holds a copy
                    Image("AppLogo")
                        .resizable()
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Text("Trainy")
                        .font(.title2.bold())
                    Text("Version \(AppInfo.version) (\(AppInfo.build))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)

            Section {
                dataSource("National Rail Enquiries", detail: "Live departures and arrivals", url: "https://www.nationalrail.co.uk")
                dataSource("Realtime Trains", detail: "Timetables for later trains", url: "https://www.realtimetrains.co.uk")
                dataSource("Transitous", detail: "Routes with a change, and their data sources", url: JourneyPlanner.sourcesURL.absoluteString)
                dataSource("Transport for London", detail: "How the Tube is running, on a change across London", url: "https://tfl.gov.uk")
            } header: {
                Text("Train Data")
            } footer: {
                Text("Live times come from National Rail's Darwin feed, which covers trains leaving within about four hours. Realtime Trains provides the timetable for anything later. Routes with a change are planned by Transitous, a free service run by volunteers, and each train on them is then followed through the other two.")
            }
            .listRowBackground(Color.card)
        }
        .appListSurface()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func dataSource(_ name: String, detail: String, url: String) -> some View {
        if let url = URL(string: url) {
            Link(destination: url) {
                LabeledContent {
                    Image(systemName: "arrow.up.right")
                } label: {
                    Text(name)
                    Text(detail)
                }
            }
            .tint(.primary)
        }
    }
}

#Preview {
    ProfileView()
        .modelContainer(for: [SavedTrain.self, SavedRoute.self], inMemory: true)
}
