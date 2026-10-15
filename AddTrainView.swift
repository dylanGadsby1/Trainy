import SwiftUI
import SwiftData

// MARK: - Add Train

/// The search the user is filling in. ContentView holds it, so it is still there the next
/// time Add Train opens.
struct TrainSearchDraft {
    var origin: UKStation?
    var destination: UKStation?
    var date = Date()
}

/// A search that has been run: what the results screen is showing.
struct TrainSearchQuery: Hashable {
    let origin: UKStation
    let destination: UKStation
    let date: Date
}

/// Add Train, as a sheet of its own: the search form, then its results, then one train's
/// details with the button that adds it.
struct AddTrainView: View {
    @Binding var draft: TrainSearchDraft
    /// Set when the train picked is to be the next one of this saved train's journey
    var continuing: SavedTrain? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedRoute.addedAt, order: .reverse) private var savedRoutes: [SavedRoute]

    @State private var showingOriginPicker = false
    @State private var showingDestinationPicker = false
    /// The search whose results are showing
    @State private var search: TrainSearchQuery?
    /// The saved route whose commute is being set
    @State private var commuteRoute: SavedRoute?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let previous = continuing?.service {
                        ContinuingCard(previous: previous)
                    }

                    routeCard

                    Button {
                        if let origin = draft.origin, let destination = draft.destination {
                            search = TrainSearchQuery(origin: origin, destination: destination, date: draft.date)
                        }
                    } label: {
                        Label("Search Trains", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.primary)
                    .disabled(draft.origin == nil || draft.destination == nil)

                    if !savedRoutes.isEmpty {
                        savedRoutesSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.surface)
            .navigationTitle(continuing == nil ? "Add Train" : "Add Next Train")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if let origin = draft.origin, let destination = draft.destination {
                    ToolbarItem(placement: .primaryAction) {
                        SaveRouteButton(originCRS: origin.crs, destinationCRS: destination.crs)
                    }
                }
            }
            .navigationDestination(item: $search) { query in
                TrainResultsView(query: query, continuing: continuing) {
                    dismiss()
                }
            }
            .sheet(item: $commuteRoute) { route in
                NavigationStack {
                    CommuteEditorView(route: route)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { commuteRoute = nil }
                            }
                        }
                }
            }
        }
        .onAppear {
            // A search left half-filled yesterday should not ask about yesterday
            if draft.date < Date() {
                draft.date = Date()
            }
        }
    }

    // MARK: - Route

    private var routeCard: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Button {
                    showingOriginPicker = true
                } label: {
                    stationRow("From", station: draft.origin, placeholder: "Choose a station", isDestination: false)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingOriginPicker) {
                    StationPickerView(selectedStation: $draft.origin)
                }

                Divider()
                    .padding(.leading, 66)

                Button {
                    showingDestinationPicker = true
                } label: {
                    stationRow("To", station: draft.destination, placeholder: "Choose a station", isDestination: true)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingDestinationPicker) {
                    StationPickerView(selectedStation: $draft.destination)
                }
            }
            // Sits on the line between From and To, whatever height the rows come to
            .overlay(alignment: .trailing) {
                swapButton
                    .padding(.trailing, 10)
            }

            Divider()
                .padding(.leading, 66)

            // Date & Time Picker
            HStack(spacing: 14) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.brand)
                    .frame(width: 36, height: 36)
                    .background(Color.brandTint, in: Circle())
                    .accessibilityHidden(true)
                DatePicker(
                    "Leaving",
                    selection: $draft.date,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .cardSurface()
    }

    private func stationRow(_ label: String, station: UKStation?, placeholder: String, isDestination: Bool) -> some View {
        HStack(spacing: 14) {
            // Hollow where the journey starts, solid where it ends
            ZStack {
                Circle()
                    .fill(Color.brandTint)
                    .frame(width: 36, height: 36)
                if isDestination {
                    Circle()
                        .fill(Color.brand)
                        .frame(width: 11, height: 11)
                } else {
                    Circle()
                        .strokeBorder(Color.brand, lineWidth: 2.5)
                        .frame(width: 11, height: 11)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.inkSecondary)
                Text(station?.name ?? placeholder)
                    .font(.body.weight(.medium))
                    .foregroundStyle(station == nil ? Color.inkSecondary : Color.ink)
                    .lineLimit(1)
            }
            // Room for the swap button
            Spacer(minLength: 52)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    /// Turns the journey round, for the way back.
    private var swapButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                (draft.origin, draft.destination) = (draft.destination, draft.origin)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.ink)
                .frame(width: 36, height: 36)
                .background(Color.surface, in: Circle())
                .overlay(Circle().strokeBorder(Color.divider, lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(draft.origin == nil && draft.destination == nil)
        .accessibilityLabel("Swap stations")
    }

    // MARK: - Saved Routes

    private var savedRoutesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Saved routes")
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(savedRoutes.enumerated()), id: \.element.id) { index, route in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 66)
                    }
                    savedRouteRow(route)
                }
            }
            .cardSurface()

            Text("Touch and hold a route to make it your commute. Trainy then follows your usual train for you.")
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private func savedRouteRow(_ route: SavedRoute) -> some View {
        if let origin = route.origin, let destination = route.destination {
            HStack(spacing: 0) {
                // The route as saved: one tap searches it from now
                Button {
                    search(from: origin, to: destination)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: route.isCommute ? "briefcase.fill" : "star.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.brand)
                            .frame(width: 36, height: 36)
                            .background(Color.brandTint, in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(origin.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.ink)
                                .lineLimit(1)
                            Text("to \(destination.name)")
                                .font(.footnote)
                                .foregroundStyle(Color.inkSecondary)
                                .lineLimit(1)
                            if let commute = route.commuteSummary {
                                Text("Commute · \(commute)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.brand)
                                    .lineLimit(1)
                            }
                            EngineeringWorksBadge(originCRS: route.originCRS, destinationCRS: route.destinationCRS)
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(.leading, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // The way back
                Button {
                    search(from: destination, to: origin)
                } label: {
                    Label("Return", systemImage: "arrow.uturn.left")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(Color.subtleFill, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
                .accessibilityLabel("Search return journey")
            }
            .contextMenu {
                Button(route.isCommute ? "Edit Commute" : "Set as Commute", systemImage: "briefcase") {
                    commuteRoute = route
                }
                Button("Remove Route", systemImage: "star.slash", role: .destructive) {
                    modelContext.delete(route)
                    try? modelContext.save()
                }
            }
        }
    }

    /// Fills in the stations and shows trains leaving from now.
    private func search(from origin: UKStation, to destination: UKStation) {
        draft.origin = origin
        draft.destination = destination
        draft.date = Date()
        search = TrainSearchQuery(origin: origin, destination: destination, date: draft.date)
    }
}

// MARK: - Save Route Button

/// A star that saves the route between two stations, or removes it once saved. For a toolbar.
struct SaveRouteButton: View {
    let originCRS: String
    let destinationCRS: String

    @Environment(\.modelContext) private var modelContext
    @Query private var routes: [SavedRoute]

    private var saved: SavedRoute? {
        routes.first { $0.originCRS == originCRS && $0.destinationCRS == destinationCRS }
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if let saved {
                modelContext.delete(saved)
            } else {
                modelContext.insert(SavedRoute(originCRS: originCRS, destinationCRS: destinationCRS))
            }
            try? modelContext.save()
        } label: {
            Image(systemName: saved == nil ? "star" : "star.fill")
        }
        .accessibilityLabel(saved == nil ? "Save route" : "Remove saved route")
    }
}

// MARK: - Recent Station Searches Manager

class RecentStationSearches {
    /// Also synced through iCloud (CloudSync)
    static let key = "recentStationCRSCodes"
    private static let maxCount = 15

    static func load() -> [UKStation] {
        let codes = UserDefaults.standard.stringArray(forKey: key) ?? []
        return codes.compactMap { crs in ukStations.first { $0.crs == crs } }
    }

    static func record(_ station: UKStation) {
        var codes = UserDefaults.standard.stringArray(forKey: key) ?? []
        codes.removeAll { $0 == station.crs }
        codes.insert(station.crs, at: 0)
        if codes.count > maxCount { codes = Array(codes.prefix(maxCount)) }
        UserDefaults.standard.set(codes, forKey: key)
    }
}

// MARK: - Station Picker View

struct StationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedStation: UKStation?
    @State private var searchText = ""
    @State private var recentStations: [UKStation] = []

    /// Best first: the station whose code was typed, then names that start with the text,
    /// then names with a word that does ("Cross" finds "London Kings Cross"), then the rest.
    var filteredStations: [UKStation] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }

        func rank(_ station: UKStation) -> Int? {
            if station.crs.caseInsensitiveCompare(query) == .orderedSame { return 0 }
            let name = station.name.lowercased(), text = query.lowercased()
            if name.hasPrefix(text) { return 1 }
            if name.split(separator: " ").contains(where: { $0.hasPrefix(text) }) { return 2 }
            if name.contains(text) { return 3 }
            return nil
        }

        return ukStations
            .compactMap { station in rank(station).map { (station, $0) } }
            .sorted { ($0.1, $0.0.name) < ($1.1, $1.0.name) }
            .map(\.0)
    }

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    if recentStations.isEmpty {
                        // Empty state — no searches yet
                        ContentUnavailableView(
                            "No Recent Stations",
                            systemImage: "clock.arrow.circlepath",
                            description: Text("Start typing to find a station.")
                        )
                        .listRowSeparator(.hidden)
                    } else {
                        Section(header: Text("Recent")) {
                            ForEach(recentStations) { station in
                                stationRow(station)
                            }
                        }
                    }
                } else {
                    if filteredStations.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .listRowSeparator(.hidden)
                    } else {
                        Section(header: Text("Results")) {
                            ForEach(filteredStations) { station in
                                stationRow(station)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Station name or code")
            .navigationTitle("Select Station")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                recentStations = RecentStationSearches.load()
            }
        }
    }

    @ViewBuilder
    private func stationRow(_ station: UKStation) -> some View {
        Button {
            RecentStationSearches.record(station)
            selectedStation = station
            dismiss()
        } label: {
            HStack {
                Text(station.name)
                    .foregroundStyle(Color.ink)
                Spacer()
                Text(station.crs)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.inkSecondary)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Search Results

struct TrainResultsView: View {
    let query: TrainSearchQuery
    /// Set when the train picked is to be the next one of this saved train's journey
    var continuing: SavedTrain? = nil
    /// Called once a train has been added to My Trains
    var onAdded: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var savedTrains: [SavedTrain]

    @State private var services: [DarwinServiceAdapter] = []
    @State private var allFetchedServices: [DarwinServiceAdapter] = []
    @State private var loadedCount = 0
    @State private var isLoading = true
    @State private var hasSearched = false
    @State private var errorMessage: String?
    /// The train whose details are showing
    @State private var selectedTrain: DarwinServiceAdapter?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SheetHeader("\(query.origin.name) to \(query.destination.name)", eyebrow: heading)

                // Only for a saved route: its path is what works are matched against
                EngineeringWorksCard(originCRS: query.origin.crs, destinationCRS: query.destination.crs)

                if isLoading {
                    ProgressView("Searching departures…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let errorMessage = errorMessage {
                    ContentUnavailableView {
                        Label("Couldn't Load Trains", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try Again") {
                            Task { await fetchDepartures() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 24)
                } else if services.isEmpty {
                    // Kept small: the routes with a change, just below, are the answer
                    Label("No direct trains at this time.", systemImage: "tram.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .cardSurface()
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(services) { service in
                            Button {
                                selectedTrain = service
                            } label: {
                                DepartureRow(train: service, savedNote: savedNote(for: service))
                            }
                            .buttonStyle(.plain)
                        }

                        if loadedCount < allFetchedServices.count {
                            Button("Show more trains") {
                                showMoreDepartures()
                            }
                            .buttonStyle(.secondary)
                            .padding(.top, 8)
                        }
                    }
                }

                // Once the direct trains are known: with none, the routes with a change are the answer.
                // Not while a journey is being built a train at a time: each change is its own search.
                if !isLoading, errorMessage == nil, continuing == nil {
                    JourneyOptionsSection(query: query, loadsAtOnce: services.isEmpty, onAdded: onAdded)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.surface)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SaveRouteButton(originCRS: query.origin.crs, destinationCRS: query.destination.crs)
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedTrain != nil },
            set: { if !$0 { selectedTrain = nil } }
        )) {
            if let train = selectedTrain {
                // The details a saved train shows, with the button that saves this one
                JourneyDashboardView(
                    journey: train.toTrainJourney(),
                    rawService: train,
                    onAdd: { add(train) },
                    addTitle: continuing == nil ? "Add to My Trains" : "Add as Next Train",
                    savedNote: savedNote(for: train)
                )
            }
        }
        .task {
            // Coming back from a train's details is not a reason to search again
            if !hasSearched {
                await fetchDepartures()
            }
        }
    }

    /// Names the day when the search is not for today, since the rows only show times.
    private var heading: String {
        guard !Calendar.current.isDateInToday(query.date) else { return "Departures" }
        let day = query.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return "Departures · \(day)"
    }

    /// Where the user already has this train, if they do.
    private func savedNote(for train: DarwinServiceAdapter) -> String? {
        guard let saved = savedTrains.first(where: { $0.service?.isSameJourney(as: train) == true }) else { return nil }
        if saved.isPast { return "In Rail History" }
        // A train followed on its own can still become the next one of this journey
        guard let continuing else { return "In My Trains" }
        return saved === continuing || (saved.journeyID != nil && saved.journeyID == continuing.journeyID) ? "In This Journey" : nil
    }

    private func add(_ train: DarwinServiceAdapter) {
        guard savedNote(for: train) == nil else { return }
        if let continuing {
            continuing.addNext(train, in: modelContext)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onAdded()
            return
        }
        guard let data = try? JSONEncoder().encode(train) else { return }
        modelContext.insert(SavedTrain(id: train.id, serviceData: data))
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onAdded()
    }

    private func fetchDepartures() async {
        hasSearched = true
        isLoading = true
        errorMessage = nil

        do {
            // Live trains from Darwin and timetabled trains from Realtime Trains, as one list
            let trains = try await TrainSearch.departures(from: query.origin.crs, to: query.destination.crs, at: query.date)
            allFetchedServices = trains
            loadedCount = min(10, trains.count)
            services = Array(trains.prefix(10))
        } catch {
            // The screen was left mid-search: nothing went wrong, so search again on return
            if Task.isCancelled {
                hasSearched = false
                return
            }
            errorMessage = TrainSearch.message(for: error)
        }
        isLoading = false
    }

    private func showMoreDepartures() {
        let nextCount = min(loadedCount + 10, allFetchedServices.count)
        services = Array(allFetchedServices.prefix(nextCount))
        loadedCount = nextCount
    }
}

#Preview {
    AddTrainView(draft: .constant(TrainSearchDraft()))
        .modelContainer(for: [SavedTrain.self, SavedRoute.self], inMemory: true)
}

// MARK: - Continuing a Journey

/// Above the search when the train picked will be the next one of a journey: which train
/// it follows, and when that gets in.
struct ContinuingCard: View {
    let previous: DarwinServiceAdapter

    var body: some View {
        let arrivalCRS = previous.userSearchDestinationCRS ?? previous.destinationCRS
        let arrival = previous.userSearchDestinationArrivalTime ?? previous.userSearchDestinationScheduledArrivalTime

        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.brand)
                .frame(width: 36, height: 36)
                .background(Color.brandTint, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("After the \(previous.scheduledDeparture) to \(UKStation.name(for: arrivalCRS))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ink)
                Text("Due in at \(arrival ?? "--:--"). Choose where the next train goes, or change From if you'll walk to another station.")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Departure Row

/// One train in the search results. Every row is the same route, so the row leads with what
/// tells the trains apart: when each leaves and arrives.
struct DepartureRow: View {
    let train: DarwinServiceAdapter
    /// Where the user already has this train ("In My Trains"), if they do
    var savedNote: String? = nil

    /// The platform only once there is one: "Platform TBC" on every row says nothing
    private var facts: String {
        [train.durationText, DarwinServiceAdapter.isKnownPlatform(train.platform) ? "Platform \(train.platform)" : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    time(
                        scheduled: train.scheduledDeparture,
                        expected: train.realtimeDeparture,
                        isLate: train.departureDelayMinutes > 0
                    )
                    Image(systemName: "arrow.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.inkTertiary)
                    time(
                        scheduled: train.userSearchDestinationScheduledArrivalTime ?? train.userSearchDestinationArrivalTime,
                        expected: train.userSearchDestinationArrivalTime,
                        isLate: train.arrivalDelayMinutes > 0
                    )
                }
                .monospacedDigit()

                HStack(spacing: 6) {
                    // A logo stands apart by itself; a name needs a dot before what follows
                    if OperatorBrand.from(code: train.atocCode) != nil {
                        OperatorLogoBadge(atocCode: train.atocCode, compact: true)
                    } else {
                        Text(train.atocName ?? "Unknown operator")
                        if !facts.isEmpty {
                            Text("·")
                        }
                    }
                    // A long operator name gives way before the duration and platform do
                    Text(facts)
                        .layoutPriority(1)
                }
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                StatusPill(train.trainStatus)
                if let savedNote {
                    Label(savedNote, systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                }
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.inkTertiary)
        }
        .padding(16)
        .cardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([train.spokenSummary, train.durationText.map { "takes \($0)" }, savedNote].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Shows the train's details")
    }

    /// The time to go by, large: the expected one, with the timetable's struck out when they differ.
    @ViewBuilder
    private func time(scheduled: String?, expected: String?, isLate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text((isLate ? expected : scheduled) ?? "--:--")
                .font(.title3.weight(.bold))
                .foregroundStyle(train.isCancelledService ? Color.inkSecondary : (isLate ? Color.statusDelayed : Color.ink))
                .strikethrough(train.isCancelledService)
            if isLate, let scheduled {
                Text(scheduled)
                    .font(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .strikethrough()
            }
        }
    }
}
