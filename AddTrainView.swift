import SwiftUI

// MARK: - Add Train Sheet View

struct AddTrainSheetView: View {
    @Binding var myTrains: [RTTServiceModel]
    @Binding var selectedTab: Int
    @Binding var currentDetent: SheetDetent
    
    var body: some View {
        MapBottomSheet(detent: $currentDetent) {
            AddTrainSheetContent(myTrains: $myTrains, selectedTab: $selectedTab)
        }
    }
}

struct AddTrainSheetContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var myTrains: [RTTServiceModel]
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
                    myTrains: $myTrains,
                    selectedTab: $selectedTab,
                    showingResults: $showingResults
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NEW JOURNEY")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                            .tracking(1.5)
                        Text("Add Train")
                            .font(.system(size: 22, weight: .black))
                            .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                    VStack(spacing: 24) {
                        // Route input card
                        VStack(spacing: 0) {
                            // From
                            Button {
                                showingOriginPicker = true
                            } label: {
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
                            .sheet(isPresented: $showingOriginPicker) {
                                StationPickerView(selectedStation: $originStation)
                            }

                            Divider()
                                .padding(.leading, 66)

                            // To
                            Button {
                                showingDestinationPicker = true
                            } label: {
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

                        // Search button
                        Button {
                            guard originStation != nil && destinationStation != nil else { return }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
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
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showingResults)
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
    @Binding var myTrains: [RTTServiceModel]
    @Binding var selectedTab: Int
    @Binding var showingResults: Bool

    @Environment(\.colorScheme) private var colorScheme

    @State private var services: [RTTAPIService] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 16) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
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
                    Text("DEPARTURES")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                        .tracking(1.5)
                    Text("\(origin.crs) to \(destination.crs)")
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 16)

            if isLoading {
                VStack {
                    ProgressView("Searching live departures...")
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
                            if !myTrains.contains(where: { $0.id == service.id }) {
                                myTrains.append(service)
                            }
                            withAnimation {
                                showingResults = false
                            }
                            selectedTab = 0
                        } label: {
                            MyTrainCard(train: service)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .task {
            await fetchDepartures()
        }
    }

    private func fetchDepartures() async {
        isLoading = true
        errorMessage = nil
        do {
            let res = try await RTTService.shared.departures(from: origin.crs, on: date, to: destination.crs)
            await MainActor.run {
                // The API now filters to trains calling at our destination for us, just map the user search intent
                let filtered = (res.services ?? []).map { service -> RTTServiceModel in
                    
                    var mutableService = service
                    mutableService.userSearchOriginCRS = origin.crs
                    mutableService.userSearchDestinationCRS = destination.crs
                    
                    // We mock arrival time since intermediate points aren't returned by default
                    // In a full implementation, we'd fetch this from the service details endpoint.
                    let departureTimeStr = mutableService.scheduledDeparture
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "HH:mm"
                    if let depTime = dateFormatter.date(from: departureTimeStr) {
                        let mockArrivalTime = depTime.addingTimeInterval(3600) // +1 hour mock
                        mutableService.userSearchDestinationArrivalTime = dateFormatter.string(from: mockArrivalTime)
                    } else {
                        mutableService.userSearchDestinationArrivalTime = "--:--"
                    }
                    
                    return mutableService
                }
                self.services = filtered
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load live data. \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
}

#Preview {
    AddTrainSheetView(myTrains: .constant([]), selectedTab: .constant(2), currentDetent: .constant(.compact))
}

