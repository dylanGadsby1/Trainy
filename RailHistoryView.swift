import SwiftUI
import SwiftData

// MARK: - Past Trains View

struct PastTrainsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<SavedTrain> { $0.isPast == true }, sort: \.addedAt, order: .reverse) private var pastTrains: [SavedTrain]

    @State private var trainToDelete: SavedTrain?
    @State private var showingDeleteConfirmation = false

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
                            Text("\(pastTrains.count)")
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
                                                    statusColor: service.trainStatus.color
                                                )
                                            }
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
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
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

// MARK: - Past Journey Row

struct PastJourneyRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let originCode: String
    let destinationCode: String
    let date: String
    let operator_: String
    let atocCode: String?
    let delayMinutes: Int
    let statusColor: Color

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
            }

            Spacer()

            // Delay / on time
            VStack(alignment: .trailing, spacing: 4) {
                if delayMinutes > 0 {
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
                    Text("\(pastTrains.count)")
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
                                 NavigationLink(destination: RailHistoryDetailView(train: savedTrain)) {
                                     PastJourneyRow(
                                         originCode: service.userSearchOriginCRS ?? service.originCRS,
                                         destinationCode: service.userSearchDestinationCRS ?? service.destinationCRS,
                                         date: DateFormatter.localizedString(from: savedTrain.movedToPastAt ?? savedTrain.addedAt, dateStyle: .short, timeStyle: .none),
                                         operator_: service.atocName ?? "Unknown",
                                         atocCode: service.atocCode,
                                         delayMinutes: service.delayMinutes,
                                         statusColor: service.trainStatus.color
                                     )
                                 }
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
                         }
                     }
                }
                .padding(.horizontal, 20)
            }
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
                                    
                                    if service.delayMinutes > 0 {
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
                        
                        // Delay Repay Section
                        if service.delayMinutes >= 15,
                           let brand = OperatorBrand.from(code: service.atocCode),
                           let delayRepayString = brand.delayRepayURL,
                           let delayRepayURL = URL(string: delayRepayString) {
                            
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.orange)
                                
                                Text("You may be entitled to compensation")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                                    .multilineTextAlignment(.center)
                                
                                Text("This train was delayed by \(service.delayMinutes) minutes. You can claim Delay Repay from \(brand.shortName).")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                                
                                Link(destination: delayRepayURL) {
                                    Text("Claim Delay Repay")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(Color.appBlue)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .padding(.top, 8)
                            }
                            .padding(24)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
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
