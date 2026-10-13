import SwiftUI
import SwiftData

/// Trains and journeys that finished in the current calendar month.
private func journeysThisMonth(_ items: [TravelItem]) -> Int {
    items.filter {
        Calendar.current.isDate($0.finishedAt, equalTo: Date(), toGranularity: .month)
    }.count
}

// MARK: - Past Journey Row

/// A row in Rail History: one train that has run, or a journey of several trains as one.
struct PastJourneyRow: View {
    private let originCode: String
    private let destinationCode: String
    private let finished: Date
    private let operators: [OperatorSummary.Operator]
    /// The bar down the leading edge
    private let barColor: Color
    /// How the journey went: a word for it, its colour, and the symbol or figure shown above the word
    private let outcome: (label: String, color: Color, symbol: String?, figure: String?)
    /// Minutes late at the end, for VoiceOver
    private let delayMinutes: Int
    private let claim: (note: String, isOpen: Bool)?
    /// "1 change", on a journey of several trains
    private let changes: String?

    /// - Parameter isLeg: True for one train of a journey shown on the journey's own page,
    ///   where Delay Repay is the journey's and is not repeated on each train.
    init(train: SavedTrain, service: DarwinServiceAdapter, isLeg: Bool = false) {
        originCode = service.userSearchOriginCRS ?? service.originCRS
        destinationCode = service.userSearchDestinationCRS ?? service.destinationCRS
        finished = train.movedToPastAt ?? train.addedAt
        operators = [service].operators
        barColor = service.trainStatus.color
        delayMinutes = service.isCancelledService ? 0 : service.delayMinutes
        if service.isCancelledService {
            outcome = ("Cancelled", service.trainStatus.color, "xmark.circle.fill", nil)
        } else if service.delayMinutes > 0 {
            outcome = ("Delayed", service.trainStatus.color, nil, "+\(service.delayMinutes)m")
        } else {
            outcome = ("On time", .statusOnTime, "checkmark.circle.fill", nil)
        }
        claim = isLeg ? nil : Self.note(for: TravelItem.train(train).claims.map(\.claim))
        changes = nil
    }

    /// The journey from where it started to where it ended, judged by when its last train got in.
    init(journey: SavedJourney) {
        let services = journey.services
        originCode = services.first.map { $0.userSearchOriginCRS ?? $0.originCRS } ?? "UNK"
        destinationCode = services.last.map { $0.userSearchDestinationCRS ?? $0.destinationCRS } ?? "UNK"
        finished = journey.legs.map { $0.movedToPastAt ?? $0.addedAt }.max() ?? Date()
        operators = services.operators

        // Against the journey as first planned: a missed change can mean later trains that ran on time
        let delay = journey.minutesLate
        if services.contains(where: \.isCancelledService) {
            // One of its trains did not run
            outcome = ("Disrupted", .statusCancelled, "xmark.circle.fill", nil)
            delayMinutes = 0
        } else if delay > 0 {
            outcome = ("Delayed", .statusDelayed, nil, "+\(TravelStats.duration(minutes: delay))")
            delayMinutes = delay
        } else {
            outcome = ("On time", .statusOnTime, "checkmark.circle.fill", nil)
            delayMinutes = 0
        }
        barColor = outcome.color
        // One claim for the journey, by how late it ended
        claim = Self.note(for: journey.delayRepay.map { [$0.claim] } ?? [])
        changes = journey.changesText
    }

    /// A claim still open comes first; one already made is only a record.
    private static func note(for claims: [DelayRepayClaim]) -> (note: String, isOpen: Bool)? {
        if let open = claims.first(where: \.isOpen) {
            return ("Delay Repay · \(open.daysLeftText)", true)
        }
        return claims.contains { $0.claimedAt != nil } ? ("Delay Repay claimed", false) : nil
    }

    private var date: String {
        DateFormatter.localizedString(from: finished, dateStyle: .short, timeStyle: .none)
    }

    private var spokenSummary: String {
        var parts = ["\(UKStation.name(for: originCode)) to \(UKStation.name(for: destinationCode))", date]
        if let changes { parts.append(changes) }
        parts.append(delayMinutes > 0 ? "delayed \(delayMinutes) minutes" : outcome.label)
        if let claim { parts.append(claim.note) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 14) {
            // Status indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(barColor)
                .frame(width: 4, height: 44)

            // Route
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(originCode)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.inkTertiary)
                    Text(destinationCode)
                }
                .font(.headline)
                .foregroundStyle(Color.ink)

                HStack(spacing: 6) {
                    Text(date)
                    Text("·")
                    OperatorSummary(operators: operators, compact: true)
                }
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
                // One height whichever logo it is, so the rows match
                .frame(height: 22)

                if let changes {
                    Label(changes, systemImage: "arrow.triangle.swap")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                }

                if let claim {
                    // An open claim wants attention; a claimed one is only a record
                    Label(claim.note, systemImage: claim.isOpen ? "sterlingsign.circle.fill" : "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(claim.isOpen ? Color.ink : Color.inkSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // Cancelled / delay / on time
            VStack(alignment: .trailing, spacing: 2) {
                if let symbol = outcome.symbol {
                    Image(systemName: symbol)
                        .font(.title3)
                } else if let figure = outcome.figure {
                    Text(figure)
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                }
                Text(outcome.label)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(outcome.color)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.inkTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .cardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
    }
}

// MARK: - Past Trains Sheet (used by ContentView tab over the map)

struct PastTrainsSheetView: View {
    @Environment(\.modelContext) private var modelContext
    /// Every saved train, so that a journey of several is only listed once its last train has run
    @Query private var savedTrains: [SavedTrain]
    /// The rows: each train that has run, and each finished journey of several trains as one
    private var items: [TravelItem] { savedTrains.travelItems(past: true) }

    /// One train, or every train of a journey, waiting on the confirmation to remove it
    @State private var trainsToDelete: [SavedTrain] = []
    @State private var showingDeleteConfirmation = false

    @Binding var currentDetent: SheetDetent
    /// Height of the My Trains peek, so this sheet stands as far out as that one at its smallest
    var myTrainsPeekHeight: CGFloat? = nil

    var body: some View {
        MapBottomSheet(detent: $currentDetent, borrowedPeekHeight: myTrainsPeekHeight) {
            SheetHeader("Rail History") {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(journeysThisMonth(items))")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.brand)
                    Text("This month")
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        } content: {
            journeys
        }
        .confirmationDialog(
            "Remove Journey",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if !trainsToDelete.isEmpty {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        trainsToDelete.forEach(modelContext.delete)
                        try? modelContext.save()
                    }
                }
                trainsToDelete = []
            }
            Button("Cancel", role: .cancel) {
                trainsToDelete = []
            }
        } message: {
            Text("Are you sure you want to remove this journey from Rail History?")
        }
    }

    @ViewBuilder
    private var journeys: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "No Journeys Yet",
                systemImage: "tram.fill",
                description: Text("Trains you follow move here once they have run.")
            )
            .padding(.top, 16)
        } else {
            VStack(spacing: 10) {
                NavigationLink(value: RailStatsRoute()) {
                    RailStatsSummaryCard(stats: TravelStats(savedTrains))
                }
                .buttonStyle(.plain)

                ForEach(items) { item in
                    switch item {
                    case .train(let savedTrain):
                        if let service = savedTrain.service {
                            NavigationLink(value: savedTrain) {
                                PastJourneyRow(train: savedTrain, service: service)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows the journey")
                            .contextMenu { removeButton(item) }
                        }

                    case .journey(let journey):
                        NavigationLink(value: JourneyRoute(id: journey.id)) {
                            PastJourneyRow(journey: journey)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows each train of the journey")
                        .contextMenu { removeButton(item) }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func removeButton(_ item: TravelItem) -> some View {
        Button("Remove from Rail History", systemImage: "trash", role: .destructive) {
            trainsToDelete = item.legs
            showingDeleteConfirmation = true
        }
    }
}

#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()
        NavigationStack {
            PastTrainsSheetView(currentDetent: .constant(.mid))
        }
    }
    .modelContainer(for: [SavedTrain.self, SavedRoute.self], inMemory: true)
}

struct RailHistoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let train: SavedTrain

    @Query private var savedTrains: [SavedTrain]
    @State private var confirmingRemoval = false

    /// One train of a journey of several. Its Delay Repay is the journey's, by how late the
    /// journey ended, and is on the journey's page.
    private var isLegOfJourney: Bool {
        guard let id = train.journeyID else { return false }
        return savedTrains.filter { $0.journeyID == id }.count > 1
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Removing the journey leaves this screen on show while it slides away, and a
                // removed train can no longer be read
                if train.modelContext != nil, !train.isDeleted, let service = train.service {
                    // Journey Overview Card
                    Card {
                        VStack(spacing: 16) {
                            HStack {
                                field("Origin", alignment: .leading) {
                                    Text(service.userSearchOriginCRS ?? service.originCRS)
                                        .font(.title.weight(.bold))
                                        .accessibilityLabel(UKStation.name(for: service.userSearchOriginCRS ?? service.originCRS))
                                }
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(Color.inkTertiary)
                                    .accessibilityHidden(true)
                                Spacer()
                                field("Destination", alignment: .trailing) {
                                    Text(service.userSearchDestinationCRS ?? service.destinationCRS)
                                        .font(.title.weight(.bold))
                                        .accessibilityLabel(UKStation.name(for: service.userSearchDestinationCRS ?? service.destinationCRS))
                                }
                            }

                            Divider()

                            // Time and Status
                            HStack(alignment: .top) {
                                field("Date", alignment: .leading) {
                                    Text(DateFormatter.localizedString(from: train.movedToPastAt ?? train.addedAt, dateStyle: .medium, timeStyle: .short))
                                        .font(.subheadline.weight(.semibold))
                                }

                                Spacer()

                                field("Status", alignment: .trailing) {
                                    Group {
                                        if service.isCancelledService {
                                            Text("Cancelled")
                                        } else if service.delayMinutes > 0 {
                                            Text("Delayed by \(service.delayMinutes)m")
                                        } else {
                                            Text("On time")
                                        }
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(service.trainStatus.color)
                                }
                            }

                            if let reason = service.disruptionReason {
                                Text(reason)
                                    .font(.footnote)
                                    .foregroundStyle(Color.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Divider()

                            // Operator
                            HStack {
                                Text("Operated by")
                                    .font(.footnote)
                                    .foregroundStyle(Color.inkSecondary)
                                Spacer()
                                OperatorLogoBadge(atocCode: service.atocCode, compact: false)
                                if OperatorBrand.from(code: service.atocCode) == nil {
                                    Text(service.atocName ?? "Unknown")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.ink)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }

                    // A train cancelled a short while ago may still need replacing
                    if AlternativeTrains.areWorthOffering(for: service) {
                        AlternativeTrainsCard(train: service)
                    }

                    if !isLegOfJourney, let entry = TravelItem.train(train).claims.first {
                        DelayRepaySection(train: entry.train, claim: entry.claim)
                    }
                }
            }
            .padding(20)
        }
        .background(Color.surface)
        .navigationTitle("Journey Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Remove from Rail History", systemImage: "trash") {
                    confirmingRemoval = true
                }
            }
        }
        .confirmationDialog("Remove this journey from Rail History?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
                modelContext.delete(train)
                try? modelContext.save()
            }
        }
    }

    /// A small label over a value, as the overview card sets out each fact.
    private func field<Value: View>(_ label: String, alignment: HorizontalAlignment, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
            value()
                .foregroundStyle(Color.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Delay Repay

/// The claim card on a past journey: claim link while the window is open, then claimed or closed.
struct DelayRepaySection: View {
    @Environment(\.modelContext) private var modelContext
    let train: SavedTrain
    let claim: DelayRepayClaim

    private var isClaimed: Bool { claim.claimedAt != nil }

    private var title: String {
        if isClaimed { return "Delay Repay claimed" }
        return claim.isOpen ? "You may be entitled to compensation" : "Delay Repay window closed"
    }

    private var message: String {
        if let claimedAt = claim.claimedAt {
            return "Marked as claimed on \(claimedAt.formatted(date: .abbreviated, time: .omitted))."
        }
        guard claim.isOpen else {
            return "\(claim.brand.shortName) accepts claims for \(DelayRepayClaim.claimWindowDays) days after the journey."
        }
        if claim.isJourney {
            // A journey is claimed for as a whole, from the operator whose train went wrong first
            return claim.isCancelled
                ? "A train on this journey was cancelled. If you reached your destination \(claim.brand.delayRepayThreshold) or more minutes late, you can claim Delay Repay from \(claim.brand.shortName)."
                : "This journey ended \(claim.delayMinutes) minutes later than planned. Delay Repay is for the whole journey, and is claimed from \(claim.brand.shortName), whose train went wrong first."
        }
        if claim.isCancelled {
            return "This train was cancelled. If you reached your destination \(claim.brand.delayRepayThreshold) or more minutes late on another train, you can claim Delay Repay from \(claim.brand.shortName)."
        }
        return "This train was delayed by \(claim.delayMinutes) minutes. You can claim Delay Repay from \(claim.brand.shortName)."
    }

    var body: some View {
        VStack(spacing: 12) {
            // Not a status colour: green, orange and red are kept for how the train ran
            Image(systemName: isClaimed ? "checkmark.circle.fill" : "sterlingsign.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(claim.isOpen ? Color.ink : Color.inkSecondary)
                .accessibilityHidden(true)

            Text(title)
                .font(.headline)
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)

            if claim.isOpen {
                StatusPill(claim.daysLeftText, color: .ink)

                Link(destination: claim.url) {
                    Text("Claim Delay Repay")
                }
                .buttonStyle(.primary)
                .padding(.top, 8)

                Button("Mark as claimed") { setClaimed(Date()) }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            } else if isClaimed {
                Button("Undo") { setClaimed(nil) }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    private func setClaimed(_ date: Date?) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        train.delayRepayClaimedAt = date
        try? modelContext.save()
        Task { await TrainAlerts.shared.refreshDelayRepayReminders(in: modelContext) }
    }
}

/// Every past journey with a Delay Repay claim still to make. Opened from Profile.
struct DelayRepayClaimsView: View {
    /// Every saved train, so that a journey of several is whole: it has one claim, for how late it ended
    @Query private var savedTrains: [SavedTrain]

    private var claimable: [TravelItem] {
        savedTrains.travelItems(past: true).filter { item in item.claims.contains { $0.claim.isOpen } }
    }

    var body: some View {
        ScrollView {
            if claimable.isEmpty {
                ContentUnavailableView(
                    "Nothing to Claim",
                    systemImage: "sterlingsign.circle",
                    description: Text("Late and cancelled journeys you can claim Delay Repay for appear here.")
                )
                .padding(.top, 60)
            } else {
                VStack(spacing: 10) {
                    ForEach(claimable) { item in
                        switch item {
                        case .train(let savedTrain):
                            if let service = savedTrain.service {
                                NavigationLink(value: savedTrain) {
                                    PastJourneyRow(train: savedTrain, service: service)
                                }
                                .buttonStyle(.plain)
                            }

                        case .journey(let journey):
                            NavigationLink(value: JourneyRoute(id: journey.id)) {
                                PastJourneyRow(journey: journey)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Color.surface)
        .navigationTitle("Delay Repay")
        .navigationBarTitleDisplayMode(.inline)
        // This page is also reached from Profile, whose own stack needs telling where these lead
        .navigationDestination(for: SavedTrain.self) { train in
            RailHistoryDetailView(train: train)
        }
        .navigationDestination(for: JourneyRoute.self) { journey in
            JourneyDetailView(journeyID: journey.id, isHistory: true)
        }
    }
}
