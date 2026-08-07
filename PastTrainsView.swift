import SwiftUI

// MARK: - Past Trains View

struct PastTrainsView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let pastJourneys: [(String, String, String, String, Int, Color)] = [
        ("EUS", "LPY", "Mon 28 Jul", "Avanti West Coast", 0, .green),
        ("LDS", "MAN", "Mon 28 Jul", "Northern Rail", 8, .orange),
        ("BHM", "EUS", "Sat 26 Jul", "Avanti West Coast", 0, .green),
        ("MAN", "LDS", "Fri 25 Jul", "Northern Rail", 3, .orange),
        ("EUS", "BHM", "Thu 24 Jul", "Avanti West Coast", 0, .green),
        ("LPY", "EUS", "Wed 23 Jul", "Avanti West Coast", 22, Color(red: 0.95, green: 0.25, blue: 0.25)),
    ]

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

            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PAST TRAINS")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                                .tracking(1.5)
                            Text("Journey History")
                                .font(.system(size: 26, weight: .black, design: .rounded))
                                .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                        }
                        Spacer()
                        // Summary stat
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("6")
                                .font(.system(size: 26, weight: .black, design: .rounded))
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
                    VStack(spacing: 10) {
                        ForEach(Array(pastJourneys.enumerated()), id: \.offset) { _, journey in
                            PastJourneyRow(
                                originCode: journey.0,
                                destinationCode: journey.1,
                                date: journey.2,
                                operator_: journey.3,
                                delayMinutes: journey.4,
                                statusColor: journey.5
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
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
                        .font(.system(size: 17, weight: .black, design: .monospaced))
                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                    Text(destinationCode)
                        .font(.system(size: 17, weight: .black, design: .monospaced))
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
                        .font(.system(size: 15, weight: .black, design: .monospaced))
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
        .background(.ultraThinMaterial)
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

    private let pastJourneys: [(String, String, String, String, Int, Color)] = [
        ("EUS", "LPY", "Mon 28 Jul", "Avanti West Coast", 0, .green),
        ("LDS", "MAN", "Mon 28 Jul", "Northern Rail", 8, .orange),
        ("BHM", "EUS", "Sat 26 Jul", "Avanti West Coast", 0, .green),
        ("MAN", "LDS", "Fri 25 Jul", "Northern Rail", 3, .orange),
        ("EUS", "BHM", "Thu 24 Jul", "Avanti West Coast", 0, .green),
        ("LPY", "EUS", "Wed 23 Jul", "Avanti West Coast", 22, Color(red: 0.95, green: 0.25, blue: 0.25)),
    ]

    var body: some View {
        // Header
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("PAST TRAINS")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                    .tracking(1.5)
                Text("Journey History")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("6")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.appBlue)
                Text("This month")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)

        // Journey list
        VStack(spacing: 10) {
            ForEach(Array(pastJourneys.enumerated()), id: \.offset) { _, journey in
                PastJourneyRow(
                    originCode: journey.0,
                    destinationCode: journey.1,
                    date: journey.2,
                    operator_: journey.3,
                    delayMinutes: journey.4,
                    statusColor: journey.5
                )
            }
        }
        .padding(.horizontal, 20)
    }
}

#Preview {
    PastTrainsView()
}
