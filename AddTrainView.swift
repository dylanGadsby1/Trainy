import SwiftUI
import SwiftData

// MARK: - Add Train Sheet View

struct AddTrainSheetView: View {
    @Binding var selectedTab: Int
    @Binding var currentDetent: SheetDetent
    
    var body: some View {
        MapBottomSheet(detent: $currentDetent) {
            AddTrainSheetContent(selectedTab: $selectedTab)
        }
    }
}

struct AddTrainSheetContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedRoute.addedAt, order: .reverse) private var savedRoutes: [SavedRoute]
    @Binding var selectedTab: Int

    @State private var originStation: UKStation?
    @State private var destinationStation: UKStation?
    @State private var showingOriginPicker = false
    @State private var showingDestinationPicker = false
    @State private var showingResults = false
    @State private var journeyDate = Date()

    var body: some View {
        Group {
            if showingResults, let o = originStation, let d = destinationStation {
                LiveDeparturesFeed(
                    origin: o,
                    destination: d,
                    date: journeyDate,
                    selectedTab: $selectedTab,
                    showingResults: $showingResults
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("NEW JOURNEY")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                                .tracking(1.5)
                            Text("Add Train")
                                .font(.system(size: 22, weight: .black))
                                .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                        }
                        Spacer()
                        if let origin = originStation, let destination = destinationStation {
                            SaveRouteButton(originCRS: origin.crs, destinationCRS: destination.crs)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                    VStack(spacing: 24) {
                        // Route input card
                        VStack(spacing: 0) {
                            // From
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showingOriginPicker = true
                            } label: {
                                fromStationRow
                            }
                            .sheet(isPresented: $showingOriginPicker) {
                                StationPickerView(selectedStation: $originStation)
                            }

                            Divider()
                                .padding(.leading, 66)

                            // To
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showingDestinationPicker = true
                            } label: {
                                toStationRow
                            }
                            .sheet(isPresented: $showingDestinationPicker) {
                                StationPickerView(selectedStation: $destinationStation)
                            }

                            Divider()
                                .padding(.leading, 66)

                            // Date & Time Picker
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.orange.opacity(0.20))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "calendar")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.orange)
                                }
                                DatePicker(
                                    "Journey Time",
                                    selection: $journeyDate,
                                    in: Date()...,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .labelsHidden()
                                .environment(\.colorScheme, colorScheme) // ensure proper coloring
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .background(Color(red: 1, green: 1, blue: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(AdaptiveColor.cardStroke.resolve(in: colorScheme), lineWidth: 1)
                        )
                        // Sits on the line between From and To
                        .overlay(alignment: .topTrailing) {
                            swapButton
                                .padding(.trailing, 16)
                                .padding(.top, Self.stationRowHeight - 18)
                        }

                        // Search button
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            guard originStation != nil && destinationStation != nil else { return }
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                                showingResults = true
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 16, weight: .bold))
                                Text("Search Trains")
                                    .font(.system(size: 16, weight: .black))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                (originStation != nil && destinationStation != nil)
                                    ? Color.appleBlack
                                    : Color.appleBlack.opacity(0.25)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .disabled(originStation == nil || destinationStation == nil)

                        if !savedRoutes.isEmpty {
                            savedRoutesSection
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: showingResults)
    }
    
    // MARK: - Saved Routes

    /// Height of the From and To rows, which the swap button is placed against
    private static let stationRowHeight: CGFloat = 64

    /// Turns the journey round, for the way back.
    private var swapButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                swap(&originStation, &destinationStation)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                .frame(width: 36, height: 36)
                .background(Color(red: 1, green: 1, blue: 1))
                .clipShape(Circle())
                .overlay(Circle().stroke(AdaptiveColor.cardStroke.resolve(in: colorScheme), lineWidth: 1))
        }
        .disabled(originStation == nil && destinationStation == nil)
        .accessibilityLabel("Swap stations")
    }

    private var savedRoutesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SAVED ROUTES")
                .font(.system(size: 11, weight: .black))
                .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                .tracking(1.5)

            VStack(spacing: 0) {
                ForEach(Array(savedRoutes.enumerated()), id: \.element.id) { index, route in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 66)
                    }
                    savedRouteRow(route)
                }
            }
            .background(Color(red: 1, green: 1, blue: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AdaptiveColor.cardStroke.resolve(in: colorScheme), lineWidth: 1)
            )
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
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.yellow.opacity(0.22))
                                .frame(width: 36, height: 36)
                            Image(systemName: "star.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.orange)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(origin.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                                .lineLimit(1)
                            Text("to \(destination.name)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                                .lineLimit(1)
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
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AdaptiveColor.subtleFill.resolve(in: colorScheme))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
                .accessibilityLabel("Search return journey")
            }
            .contextMenu {
                Button("Remove Route", systemImage: "star.slash", role: .destructive) {
                    modelContext.delete(route)
                    try? modelContext.save()
                }
            }
        }
    }

    /// Fills in the stations and shows trains leaving from now.
    private func search(from origin: UKStation, to destination: UKStation) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        originStation = origin
        destinationStation = destination
        journeyDate = Date()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            showingResults = true
        }
    }

    // MARK: - Subviews
    
    private var fromStationRow: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.20))
                    .frame(width: 36, height: 36)
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("FROM")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                    .tracking(1)
                Text(originStation?.name ?? "Select origin station")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(originStation == nil ? AdaptiveColor.tertiary.resolve(in: colorScheme) : AdaptiveColor.primary.resolve(in: colorScheme))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    
    private var toStationRow: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.20))
                    .frame(width: 36, height: 36)
                Circle()
                    .fill(Color.orange)
                    .frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("TO")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                    .tracking(1)
                Text(destinationStation?.name ?? "Select arriving station")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(destinationStation == nil ? AdaptiveColor.tertiary.resolve(in: colorScheme) : AdaptiveColor.primary.resolve(in: colorScheme))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Save Route Button

/// A star that saves the route between two stations, or removes it once saved.
struct SaveRouteButton: View {
    let originCRS: String
    let destinationCRS: String

    @Environment(\.colorScheme) private var colorScheme
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
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(saved == nil ? AdaptiveColor.primary.resolve(in: colorScheme) : .orange)
                .padding(8)
                .background(AdaptiveColor.subtleFill.resolve(in: colorScheme))
                .clipShape(Circle())
        }
        .accessibilityLabel(saved == nil ? "Save route" : "Remove saved route")
    }
}

// MARK: - Recent Station Searches Manager

class RecentStationSearches {
    private static let key = "recentStationCRSCodes"
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
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedStation: UKStation?
    @State private var searchText = ""
    @State private var recentStations: [UKStation] = []

    var filteredStations: [UKStation] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return ukStations.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.crs.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    if recentStations.isEmpty {
                        // Empty state — no searches yet
                        Section {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 32))
                                        .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                                    Text("No recent searches")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                                    Text("Start typing to find a station")
                                        .font(.system(size: 13))
                                        .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                                }
                                Spacer()
                            }
                            .padding(.vertical, 40)
                            .listRowBackground(Color.clear)
                        }
                    } else {
                        Section(header: Text("Recent Searches")) {
                            ForEach(recentStations) { station in
                                stationRow(station)
                            }
                        }
                    }
                } else {
                    if filteredStations.isEmpty {
                        Section {
                            HStack {
                                Spacer()
                                Text("No stations found")
                                    .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                                Spacer()
                            }
                            .padding(.vertical, 20)
                            .listRowBackground(Color.clear)
                        }
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
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by station name or CRS...")
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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            RecentStationSearches.record(station)
            selectedStation = station
            dismiss()
        } label: {
            HStack {
                Text(station.name)
                    .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                Spacer()
                Text(station.crs)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
            }
        }
    }
}

// MARK: - Live Departures Results View

struct LiveDeparturesFeed: View {
    let origin: UKStation
    let destination: UKStation
    let date: Date
    @Binding var selectedTab: Int
    @Binding var showingResults: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query private var savedTrains: [SavedTrain]

    @State private var services: [DarwinServiceAdapter] = []
    @State private var allFetchedServices: [DarwinServiceAdapter] = []
    @State private var loadedCount = 0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var focusedTrain: DarwinServiceAdapter.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 16) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                        showingResults = false
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                        .padding(8)
                        .background(AdaptiveColor.subtleFill.resolve(in: colorScheme))
                        .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(heading)
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                        .tracking(1.5)
                    Text("\(origin.crs) to \(destination.crs)")
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                }
                Spacer()
                SaveRouteButton(originCRS: origin.crs, destinationCRS: destination.crs)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 16)

            if isLoading {
                VStack {
                    ProgressView("Searching departures...")
                        .padding(.top, 40)
                }
                .frame(maxWidth: .infinity)
            } else if let errorMessage = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") {
                        Task { await fetchDepartures() }
                    }
                    .padding()
                }
                .padding(.top, 40)
                .frame(maxWidth: .infinity)
            } else if services.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 40))
                        .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                    Text("No trains found on this route at this time.")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                }
                .padding(.top, 40)
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(services) { service in
                        Button {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            if !savedTrains.contains(where: { $0.service?.isSameJourney(as: service) == true }) {
                                if let data = try? JSONEncoder().encode(service) {
                                    let newSavedTrain = SavedTrain(id: service.id, serviceData: data)
                                    modelContext.insert(newSavedTrain)
                                    try? modelContext.save()
                                }
                            }
                            withAnimation {
                                showingResults = false
                            }
                            selectedTab = 0
                        } label: {
                            DarwinTrainCard(train: service)
                        }
                        .buttonStyle(.plain)
                        .id(service.id)
                    }
                    
                    if loadedCount < allFetchedServices.count {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showMoreDepartures()
                        } label: {
                            Text("See more trains +")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.appleBlack)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20)
            }
        }
        .scrollPosition(id: $focusedTrain)
        .onChange(of: focusedTrain) { _, _ in
            UISelectionFeedbackGenerator().selectionChanged()
        }
        .task {
            await fetchDepartures()
        }
    }

    /// Names the day when the search is not for today, since the cards only show times.
    private var heading: String {
        guard !Calendar.current.isDateInToday(date) else { return "DEPARTURES" }
        let day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return "DEPARTURES · \(day.uppercased())"
    }

    private func fetchDepartures() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Live trains from Darwin and timetabled trains from Realtime Trains, as one list
            let trains = try await TrainSearch.departures(from: origin.crs, to: destination.crs, at: date)
            
            await MainActor.run {
                self.allFetchedServices = trains
                self.loadedCount = min(10, trains.count)
                self.services = Array(trains.prefix(10))
                self.isLoading = false
            }
        } catch let error as DarwinError {
            await MainActor.run {
                switch error {
                case .httpError(500):
                    self.errorMessage = "Darwin API server error. The National Rail service may be experiencing issues. Please try again later."
                case .invalidAccessToken:
                    self.errorMessage = "Invalid Darwin API credentials. Please check your API key."
                case .rateLimitExceeded:
                    self.errorMessage = "Too many requests. Please wait a moment and try again."
                default:
                    self.errorMessage = "Failed to load Darwin data: \(error.localizedDescription)"
                }
                self.isLoading = false
            }
        } catch let error as RTTError {
            await MainActor.run {
                switch error {
                case .authFailed:
                    self.errorMessage = "Invalid Realtime Trains credentials. Please check your refresh token."
                case .rateLimitExceeded:
                    self.errorMessage = "Too many timetable searches. Please wait a minute and try again."
                default:
                    self.errorMessage = "Failed to load the timetable: \(error.localizedDescription)"
                }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load train data: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    private func showMoreDepartures() {
        let nextCount = min(loadedCount + 10, allFetchedServices.count)
        services = Array(allFetchedServices.prefix(nextCount))
        loadedCount = nextCount
    }
}

#Preview {
    AddTrainSheetView(selectedTab: .constant(2), currentDetent: .constant(.compact))
}

// MARK: - Darwin Train Card
/// A train card specifically for Darwin services (used in the search results)
struct DarwinTrainCard: View {
    let train: DarwinServiceAdapter
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top: operator logo + status
            HStack {
                OperatorLogoBadge(atocCode: train.atocCode, compact: false)
                if OperatorBrand.from(code: train.atocCode) == nil {
                    Text(train.atocName ?? "Unknown")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                        .lineLimit(1)
                }
                Spacer()
                Text(train.trainStatus.label)
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(train.trainStatus.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(train.trainStatus.color.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(.bottom, 10)

            // Route
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(train.userSearchOriginCRS ?? (train.originCRS.isEmpty ? "UNK" : train.originCRS))
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(train.scheduledDeparture)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(train.departureDelayMinutes > 0 ? AdaptiveColor.tertiary.resolve(in: colorScheme) : AdaptiveColor.secondary.resolve(in: colorScheme))
                            .strikethrough(train.departureDelayMinutes > 0)

                        if train.departureDelayMinutes > 0 {
                            Text(train.realtimeDeparture)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.orange)
                        }
                    }
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                    .padding(.horizontal, 12)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(train.userSearchDestinationCRS ?? (train.destinationCRS.isEmpty ? "UNK" : train.destinationCRS))
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                    if let arrivalTime = train.userSearchDestinationArrivalTime {
                        Text(arrivalTime)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                    } else {
                        Text("--:--")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                    }
                }
            }
            .padding(.bottom, 12)

            // Platform
            HStack {
                Text("Platform")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                Spacer()
                Text(train.platform)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
            }
        }
        .padding(16)
        .background(Color(red: 1, green: 1, blue: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AdaptiveColor.cardStroke.resolve(in: colorScheme), lineWidth: 1)
        )
    }
}

