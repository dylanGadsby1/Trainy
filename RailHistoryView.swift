import SwiftUI
import SwiftData

/// Journeys that finished in the current calendar month.
private func journeysThisMonth(_ trains: [SavedTrain]) -> Int {
    trains.filter {
        Calendar.current.isDate($0.movedToPastAt ?? $0.addedAt, equalTo: Date(), toGranularity: .month)
    }.count
}

// MARK: - Past Journey Row

struct PastJourneyRow: View {
    let train: SavedTrain
    let service: DarwinServiceAdapter

    private var originCode: String { service.userSearchOriginCRS ?? service.originCRS }
    private var destinationCode: String { service.userSearchDestinationCRS ?? service.destinationCRS }

    private var date: String {
        DateFormatter.localizedString(from: train.movedToPastAt ?? train.addedAt, dateStyle: .short, timeStyle: .none)
    }

    /// How the journey went: a word for it, its colour, and the symbol or figure shown above the word
    private var outcome: (label: String, color: Color, symbol: String?, figure: String?) {
        if service.isCancelledService {
            return ("Cancelled", service.trainStatus.color, "xmark.circle.fill", nil)
        }
        if service.delayMinutes > 0 {
            return ("Delayed", service.trainStatus.color, nil, "+\(service.delayMinutes)m")
        }
        return ("On time", .statusOnTime, "checkmark.circle.fill", nil)
    }

    private var claimNote: String? {
        guard let claim = train.delayRepay else { return nil }
        if claim.isOpen { return "Delay Repay · \(claim.daysLeftText)" }
        return claim.claimedAt != nil ? "Delay Repay claimed" : nil
    }

    private var spokenSummary: String {
        var parts = ["\(UKStation.name(for: originCode)) to \(UKStation.name(for: destinationCode))", date]
        parts.append(service.delayMinutes > 0 && !service.isCancelledService
            ? "delayed \(service.delayMinutes) minutes"
            : outcome.label)
        if let claimNote { parts.append(claimNote) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 14) {
            // Status indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(service.trainStatus.color)
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
                    OperatorLogoBadge(atocCode: service.atocCode, compact: true)
                    if OperatorBrand.from(code: service.atocCode) == nil {
                        Text(service.atocName ?? "Unknown")
                            .lineLimit(1)
                    }
                }
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)

                if let claimNote {
                    // An open claim wants attention; a claimed one is only a record
                    let isOpen = train.delayRepay?.isOpen == true
                    Label(claimNote, systemImage: isOpen ? "sterlingsign.circle.fill" : "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isOpen ? Color.ink : Color.inkSecondary)
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
    @Query(filter: #Predicate<SavedTrain> { $0.isPast == true }, sort: \.addedAt, order: .reverse) private var pastTrains: [SavedTrain]

    @State private var trainToDelete: SavedTrain?
    @State private var showingDeleteConfirmation = false

    @Binding var currentDetent: SheetDetent
    /// Height of the My Trains peek, so this sheet stands as far out as that one at its smallest
    var myTrainsPeekHeight: CGFloat? = nil

    var body: some View {
        MapBottomSheet(detent: $currentDetent, borrowedPeekHeight: myTrainsPeekHeight) {
            SheetHeader("Rail History") {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(journeysThisMonth(pastTrains))")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.ink)
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
                if let train = trainToDelete {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        modelContext.delete(train)
                        try? modelContext.save()
                    }
                }
                trainToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                trainToDelete = nil
            }
        } message: {
            Text("Are you sure you want to remove this journey from Rail History?")
        }
    }

    @ViewBuilder
    private var journeys: some View {
        if pastTrains.isEmpty {
            ContentUnavailableView(
                "No Journeys Yet",
                systemImage: "tram.fill",
                description: Text("Trains you follow move here once they have run.")
            )
            .padding(.top, 16)
        } else {
            VStack(spacing: 10) {
                ForEach(pastTrains) { savedTrain in
                    if let service = savedTrain.service {
                        NavigationLink(value: savedTrain) {
                            PastJourneyRow(train: savedTrain, service: service)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows the journey")
                        .contextMenu {
                            Button("Remove from Rail History", systemImage: "trash", role: .destructive) {
                                trainToDelete = savedTrain
                                showingDeleteConfirmation = true
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
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

    @State private var confirmingRemoval = false

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

                    if let claim = train.delayRepay {
                        DelayRepaySection(train: train, claim: claim)
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
private struct DelayRepaySection: View {
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
    @Query(filter: #Predicate<SavedTrain> { $0.isPast == true }, sort: \.addedAt, order: .reverse) private var pastTrains: [SavedTrain]

    private var claimable: [SavedTrain] {
        pastTrains.filter { $0.delayRepay?.isOpen == true }
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
                    ForEach(claimable) { savedTrain in
                        if let service = savedTrain.service {
                            NavigationLink(destination: RailHistoryDetailView(train: savedTrain)) {
                                PastJourneyRow(train: savedTrain, service: service)
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
    }
}
