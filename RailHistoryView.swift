import SwiftUI
import SwiftData

/// Journeys that finished in the current calendar month.
private func journeysThisMonth(_ trains: [SavedTrain]) -> Int {
    trains.filter {
        Calendar.current.isDate($0.movedToPastAt ?? $0.addedAt, equalTo: Date(), toGranularity: .month)
    }.count
}

// MARK: - Past Trains View

struct PastTrainsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<SavedTrain> { $0.isPast == true }, sort: \.addedAt, order: .reverse) private var pastTrains: [SavedTrain]

    @State private var trainToDelete: SavedTrain?
    @State private var showingDeleteConfirmation = false
    @State private var focusedTrain: String?

    var body: some View {
        ZStack {
            Color(red: 1, green: 1, blue: 1)
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("RAIL HISTORY")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                                .tracking(1.5)
                            Text("Rail History")
                                .font(.system(size: 26, weight: .black))
                                .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                        }
                        Spacer()
                        // Summary stat
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(journeysThisMonth(pastTrains))")
                                .font(.system(size: 26, weight: .black))
                                .foregroundColor(.appBlue)
                            Text("This month")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 20)

                    // Journey list
                    Group {
                        if pastTrains.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "tram.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                                Text("you haven't caught any trains yet")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 60)
                            .padding(.horizontal, 20)
                        } else {
                            VStack(spacing: 10) {
                            ForEach(pastTrains) { savedTrain in
                                    if let service = savedTrain.service {
                                        ZStack(alignment: .topTrailing) {
                                            NavigationLink(destination: RailHistoryDetailView(train: savedTrain)) {
                                                PastJourneyRow(
                                                    originCode: service.userSearchOriginCRS ?? service.originCRS,
                                                    destinationCode: service.userSearchDestinationCRS ?? service.destinationCRS,
                                                    date: DateFormatter.localizedString(from: savedTrain.movedToPastAt ?? savedTrain.addedAt, dateStyle: .short, timeStyle: .none),
                                                    operator_: service.atocName ?? "Unknown",
                                                    atocCode: service.atocCode,
                                                    delayMinutes: service.delayMinutes,
                                                    isCancelled: service.isCancelledService,
                                                    statusColor: service.trainStatus.color,
                                                    claim: savedTrain.delayRepay
                                                )
                                            }
                                            .simultaneousGesture(TapGesture().onEnded {
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            })
                                            .buttonStyle(.plain)

                                            // Delete button
                                            Button {
                                                trainToDelete = savedTrain
                                                showingDeleteConfirmation = true
                                            } label: {
                                                ZStack {
                                                    Circle()
                                                        .fill(.regularMaterial)
                                                        .frame(width: 24, height: 24)
                                                        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
                                                    Image(systemName: "xmark")
                                                        .font(.system(size: 9, weight: .black))
                                                        .foregroundColor(.primary)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            .offset(x: 6, y: -6)
                                        }
                                        .id(savedTrain.id)
                                    }
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .scrollPosition(id: $focusedTrain)
            .onChange(of: focusedTrain) { _, _ in
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
        .confirmationDialog(
            "Remove Train",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                if let train = trainToDelete {
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
}

// MARK: - Past Journey Row

struct PastJourneyRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let originCode: String
    let destinationCode: String
    let date: String
    let operator_: String
    let atocCode: String?
    let delayMinutes: Int
    let isCancelled: Bool
    let statusColor: Color
    var claim: DelayRepayClaim? = nil

    var body: some View {
        HStack(spacing: 16) {
            // Status indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(statusColor)
                .frame(width: 4, height: 48)

            // Route
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(originCode)
                        .font(.system(size: 17, weight: .black))
                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                    Text(destinationCode)
                        .font(.system(size: 17, weight: .black))
                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                }
                HStack(spacing: 6) {
                    Text(date)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                    Text("·")
                        .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                    OperatorLogoBadge(atocCode: atocCode, compact: true)
                    if OperatorBrand.from(code: atocCode) == nil {
                        Text(operator_)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                    }
                }
                if let claim, claim.isOpen {
                    Label("Delay Repay · \(claim.daysLeftText)", systemImage: "sterlingsign.circle.fill")
                        .lineLimit(1)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                } else if claim?.claimedAt != nil {
                    Label("Delay Repay claimed", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.green)
                }
            }

            Spacer()

            // Cancelled / delay / on time
            VStack(alignment: .trailing, spacing: 4) {
                if isCancelled {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(statusColor)
                    Text("CANCELLED")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(statusColor.opacity(0.7))
                        .tracking(0.5)
                } else if delayMinutes > 0 {
                    Text("+\(delayMinutes)m")
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(statusColor)
                    Text("DELAYED")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(statusColor.opacity(0.7))
                        .tracking(0.5)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.green)
                    Text("ON TIME")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.green.opacity(0.7))
                        .tracking(0.5)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(red: 1, green: 1, blue: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AdaptiveColor.cardStroke.resolve(in: colorScheme), lineWidth: 1)
        )
    }
}

// MARK: - Past Trains Sheet (used by ContentView tab over the map)

struct PastTrainsSheetView: View {
    @Binding var currentDetent: SheetDetent
    
    var body: some View {
        MapBottomSheet(detent: $currentDetent) {
            PastTrainsSheetContent()
        }
    }
}

private struct PastTrainsSheetContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<SavedTrain> { $0.isPast == true }, sort: \.addedAt, order: .reverse) private var pastTrains: [SavedTrain]

    @State private var trainToDelete: SavedTrain?
    @State private var showingDeleteConfirmation = false
    @State private var focusedTrain: String?

    var body: some View {
        Group {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RAIL HISTORY")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                        .tracking(1.5)
                    Text("Rail History")
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(journeysThisMonth(pastTrains))")
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(.appBlue)
                    Text("This month")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)

            // Journey list
            if pastTrains.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 40))
                        .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                    Text("you haven't caught any trains yet")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
                .padding(.horizontal, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(pastTrains) { savedTrain in
                         if let service = savedTrain.service {
                             ZStack(alignment: .topTrailing) {
                                 NavigationLink(value: savedTrain) {
                                     PastJourneyRow(
                                         originCode: service.userSearchOriginCRS ?? service.originCRS,
                                         destinationCode: service.userSearchDestinationCRS ?? service.destinationCRS,
                                         date: DateFormatter.localizedString(from: savedTrain.movedToPastAt ?? savedTrain.addedAt, dateStyle: .short, timeStyle: .none),
                                         operator_: service.atocName ?? "Unknown",
                                         atocCode: service.atocCode,
                                         delayMinutes: service.delayMinutes,
                                         isCancelled: service.isCancelledService,
                                         statusColor: service.trainStatus.color,
                                         claim: savedTrain.delayRepay
                                     )
                                 }
                                 .simultaneousGesture(TapGesture().onEnded {
                                     UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                 })
                                 .buttonStyle(.plain)

                                 // Delete button
                                 Button {
                                     trainToDelete = savedTrain
                                     showingDeleteConfirmation = true
                                 } label: {
                                     ZStack {
                                         Circle()
                                             .fill(.regularMaterial)
                                             .frame(width: 24, height: 24)
                                             .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
                                         Image(systemName: "xmark")
                                             .font(.system(size: 9, weight: .black))
                                             .foregroundColor(.primary)
                                     }
                                 }
                                 .buttonStyle(.plain)
                                 .offset(x: 6, y: -6)
                             }
                             .id(savedTrain.id)
                         }
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
        .confirmationDialog(
            "Remove Train",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let train = trainToDelete {
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
}

#Preview {
    PastTrainsView()
}
struct RailHistoryDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    let train: SavedTrain
    
    var body: some View {
        ZStack {
            Color(red: 1, green: 1, blue: 1) // Using the app's background logic
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    if let service = train.service {
                        // Journey Overview Card
                        VStack(spacing: 16) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("ORIGIN")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                                    Text(service.userSearchOriginCRS ?? service.originCRS)
                                        .font(.system(size: 28, weight: .black))
                                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                                }
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("DESTINATION")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                                    Text(service.userSearchDestinationCRS ?? service.destinationCRS)
                                        .font(.system(size: 28, weight: .black))
                                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                                }
                            }
                            
                            Divider()
                            
                            // Time and Status
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("DATE")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                                    Text(DateFormatter.localizedString(from: train.movedToPastAt ?? train.addedAt, dateStyle: .medium, timeStyle: .short))
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("STATUS")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                                    
                                    if service.isCancelledService {
                                        Text("Cancelled")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(service.trainStatus.color)
                                    } else if service.delayMinutes > 0 {
                                        Text("Delayed by \(service.delayMinutes)m")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(service.trainStatus.color)
                                    } else {
                                        Text("On Time")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(service.trainStatus.color)
                                    }
                                }
                            }
                            
                            Divider()
                            
                            // Operator
                            HStack {
                                Text("OPERATED BY")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                                Spacer()
                                OperatorLogoBadge(atocCode: service.atocCode, compact: false)
                                if OperatorBrand.from(code: service.atocCode) == nil {
                                    Text(service.atocName ?? "Unknown")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                                }
                            }
                        }
                        .padding(20)
                        .background(Color(red: 1, green: 1, blue: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AdaptiveColor.cardStroke.resolve(in: colorScheme), lineWidth: 1)
                        )
                        
                        if let claim = train.delayRepay {
                            DelayRepaySection(train: train, claim: claim)
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Journey Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Delay Repay

/// The claim card on a past journey: claim link while the window is open, then claimed or closed.
private struct DelayRepaySection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    let train: SavedTrain
    let claim: DelayRepayClaim

    private var tint: Color {
        if claim.claimedAt != nil { return .green }
        return claim.isOpen ? .orange : .gray
    }

    private var title: String {
        if claim.claimedAt != nil { return "Delay Repay claimed" }
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
            Image(systemName: claim.claimedAt != nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(tint)

            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            if claim.isOpen {
                Text(claim.daysLeftText.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.orange)
                    .tracking(0.5)

                Link(destination: claim.url) {
                    Text("Claim Delay Repay")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.appBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.top, 8)

                Button("Mark as claimed") { setClaimed(Date()) }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.appBlue)
                    .padding(.top, 4)
            } else if claim.claimedAt != nil {
                Button("Undo") { setClaimed(nil) }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.appBlue)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.3), lineWidth: 1)
        )
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
        ZStack {
            Color(red: 1, green: 1, blue: 1)
                .ignoresSafeArea()

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
                                    PastJourneyRow(
                                        originCode: service.userSearchOriginCRS ?? service.originCRS,
                                        destinationCode: service.userSearchDestinationCRS ?? service.destinationCRS,
                                        date: DateFormatter.localizedString(from: savedTrain.movedToPastAt ?? savedTrain.addedAt, dateStyle: .short, timeStyle: .none),
                                        operator_: service.atocName ?? "Unknown",
                                        atocCode: service.atocCode,
                                        delayMinutes: service.delayMinutes,
                                        isCancelled: service.isCancelledService,
                                        statusColor: service.trainStatus.color,
                                        claim: savedTrain.delayRepay
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Delay Repay")
        .navigationBarTitleDisplayMode(.inline)
    }
}
