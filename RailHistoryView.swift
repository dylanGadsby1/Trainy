import SwiftUI
import SwiftData

// MARK: - Rail History View

struct RailHistoryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query(filter: #Predicate<SavedTrain> { $0.isPast == true }, sort: \.addedAt, order: .reverse) private var railHistory: [SavedTrain]

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
                            Text("\(railHistory.count)")
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
                        if railHistory.isEmpty {
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
                                ForEach(railHistory) { savedTrain in
                                    if let service = savedTrain.service {
                                        RailHistoryJourneyRow(
                                            originCode: service.userSearchOriginCRS ?? service.originCRS,
                                            destinationCode: service.userSearchDestinationCRS ?? service.destinationCRS,
                                            date: DateFormatter.localizedString(from: savedTrain.addedAt, dateStyle: .short, timeStyle: .none),
                                            operator_: service.atocName ?? "Unknown",
                                            delayMinutes: service.delayMinutes,
                                            statusColor: service.trainStatus.color
                                        )
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
    }
}

// MARK: - Rail History Journey Row

struct RailHistoryJourneyRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let originCode: String
    let destinationCode: String
    let date: String
    let operator_: String
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
                    Text(operator_)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
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

// MARK: - Rail History Sheet (used by ContentView tab over the map)

struct RailHistorySheetView: View {
    @Binding var currentDetent: SheetDetent
    
    var body: some View {
        MapBottomSheet(detent: $currentDetent) {
            RailHistorySheetContent()
        }
    }
}

private struct RailHistorySheetContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query(filter: #Predicate<SavedTrain> { $0.isPast == true }, sort: \.addedAt, order: .reverse) private var railHistory: [SavedTrain]

    var body: some View {
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
                Text("\(railHistory.count)")
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
        if railHistory.isEmpty {
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
                ForEach(railHistory) { savedTrain in
                    if let service = savedTrain.service {
                        RailHistoryJourneyRow(
                            originCode: service.userSearchOriginCRS ?? service.originCRS,
                            destinationCode: service.userSearchDestinationCRS ?? service.destinationCRS,
                            date: DateFormatter.localizedString(from: savedTrain.addedAt, dateStyle: .short, timeStyle: .none),
                            operator_: service.atocName ?? "Unknown",
                            delayMinutes: service.delayMinutes,
                            statusColor: service.trainStatus.color
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

#Preview {
    RailHistoryView()
}
