import SwiftUI

// MARK: - Add Train View

struct AddTrainView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @Binding var myTrains: [RTTServiceModel]

    @State private var originStation: UKStation?
    @State private var destinationStation: UKStation?
    @State private var showingOriginPicker = false
    @State private var showingDestinationPicker = false
    @State private var showingResults = false
    @State private var journeyDate = Date()


    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        AdaptiveColor.bgTop.resolve(in: colorScheme),
                        AdaptiveColor.bgBottom.resolve(in: colorScheme)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
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
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(AdaptiveColor.cardStroke.resolve(in: colorScheme), lineWidth: 1)
                        )

                        // Search button
                        Button {
                            guard originStation != nil && destinationStation != nil else { return }
                            showingResults = true
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
                                LinearGradient(
                                    colors: originStation != nil ? [Color.appBlue, Color.appBlueBright] : [Color.gray, Color.gray.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: (originStation != nil && destinationStation != nil ? Color.appBlue : Color.gray).opacity(0.4), radius: 12, y: 4)
                        }
                        .disabled(originStation == nil || destinationStation == nil)
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Add Train")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.appBlue)
                }
            }
            .navigationDestination(isPresented: $showingResults) {
                if let o = originStation, let d = destinationStation {
                    LiveDeparturesView(origin: o, destination: d, date: journeyDate, myTrains: $myTrains, rootDismiss: dismiss)
                }
            }
        }
    }
}

// MARK: - Station Picker View

struct StationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedStation: UKStation?
    @State private var searchText = ""

    var filteredStations: [UKStation] {
        if searchText.isEmpty {
            return ukStations
        } else {
            return ukStations.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.crs.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredStations) { station in
                Button {
                    selectedStation = station
                    dismiss()
                } label: {
                    HStack {
                        Text(station.name)
                            .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                        Spacer()
                        Text(station.crs)
                            .font(.system(.subheadline, design: .monospaced, weight: .bold))
                            .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search by station name or CRS...")
            .navigationTitle("Select Station")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Live Departures Results View

struct LiveDeparturesView: View {
    let origin: UKStation
    let destination: UKStation
    let date: Date
    @Binding var myTrains: [RTTServiceModel]
    let rootDismiss: DismissAction

    @Environment(\.colorScheme) private var colorScheme
    @State private var services: [RTTAPIService] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AdaptiveColor.bgTop.resolve(in: colorScheme),
                    AdaptiveColor.bgBottom.resolve(in: colorScheme)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if isLoading {
                ProgressView("Searching live departures...")
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
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(services) { service in
                            Button {
                                if !myTrains.contains(where: { $0.id == service.id }) {
                                    myTrains.append(service)
                                }
                                rootDismiss()
                            } label: {
                                MyTrainCard(train: service)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
        }
        .navigationTitle("Departures from \(origin.crs)")
        .task {
            await fetchDepartures()
        }
    }

    private func fetchDepartures() async {
        isLoading = true
        errorMessage = nil
        do {
            let res = try await RTTService.shared.departures(from: origin.crs, on: date)
            await MainActor.run {
                // Filter to direct trains only, setting user search intent
                let filtered = (res.services ?? []).compactMap { service -> RTTServiceModel? in
                    // Since we can't fetch calling points yet, we filter by final destination CRS
                    guard service.destinationCRS.localizedCaseInsensitiveContains(destination.crs) || 
                          service.destinationName.localizedCaseInsensitiveContains(destination.name) else {
                        return nil
                    }
                    
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
    AddTrainView(myTrains: .constant([]))
}

