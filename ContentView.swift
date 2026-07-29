
import SwiftUI

// MARK: - Mock Data Models

struct Journey {
    let origin: Station
    let destination: Station
    let intermediate: Station
    let scheduledDeparture: String
    let predictedArrival: String
    let actualArrival: String
    let delayMinutes: Int
    let confidence: Int
    let platform: Int
    let platformProbability: Int
    let trainUnit: String
    let trainType: String
    let trainCars: Int
    let inboundLateMinutes: Int
    let connectionRisk: String
    let connectionService: String
    let connectionTime: String
    let transferMinutes: Int
    let congestionAvgDelay: Int
    let progressFraction: Double
}

struct Station {
    let code: String
    let name: String
    let scheduled: String
    let actual: String
}

let mockJourney = Journey(
    origin: Station(code: "LPY", name: "Long Preston", scheduled: "11:00", actual: "11:00"),
    intermediate: Station(code: "RUG", name: "Rugby", scheduled: "11:52", actual: "11:58"),
    destination: Station(code: "EUS", name: "London Euston", scheduled: "12:45", actual: "13:01"),
    scheduledDeparture: "11:00 LPY-EUS",
    predictedArrival: "13:01",
    actualArrival: "12:45",
    delayMinutes: 16,
    confidence: 89,
    platform: 12,
    platformProbability: 98,
    trainUnit: "390151",
    trainType: "AVANTI PENDOLINO",
    trainCars: 9,
    inboundLateMinutes: 14,
    connectionRisk: "LOW RISK",
    connectionService: "14:51 Southeastern Service",
    connectionTime: "14:51",
    transferMinutes: 5,
    congestionAvgDelay: 11,
    progressFraction: 0.72
)

// MARK: - Reusable Card Background

struct GlassCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

// MARK: - Status Header Card

struct StatusHeaderCard: View {
    let journey: Journey
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "tram.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.orange)
                            Text("\(journey.delayMinutes)M DELAY PREDICTED")
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundColor(.orange)
                        }
                        Text("BASED ON INBOUND EQUIPMENT (\(journey.scheduledDeparture))")
                            .font(.system(size: 11, weight: .semibold, design: .default))
                            .foregroundColor(.white.opacity(0.55))
                            .tracking(0.5)
                    }
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 52, height: 52)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                }

                Divider().background(Color.white.opacity(0.1))

                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .shadow(color: .green, radius: 3)
                    Text("ON TIME (per departure board)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                    Spacer()
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.18))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - Dynamic Timeline Card

struct TimelineCard: View {
    let journey: Journey

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("LIVE JOURNEY", systemImage: "location.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(1)

                // Station times above
                HStack {
                    stationTimeView(station: journey.origin)
                    Spacer()
                    stationTimeView(station: journey.intermediate)
                    Spacer()
                    stationTimeView(station: journey.destination)
                }

                // Timeline bar
                GeometryReader { geo in
                    let totalWidth = geo.size.width
                    let seg1End = totalWidth * 0.45
                    let seg2End = totalWidth
                    let trainX = totalWidth * journey.progressFraction

                    ZStack(alignment: .leading) {
                        // Background track
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 5)

                        // Green segment: LPY → RUG
                        Capsule()
                            .fill(Color.green)
                            .frame(width: seg1End, height: 5)

                        // Gradient segment: RUG → EUS
                        LinearGradient(
                            colors: [.green, .orange],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .clipShape(Capsule())
                        .frame(width: seg2End - seg1End, height: 5)
                        .offset(x: seg1End)

                        // Station nodes
                        ForEach([0.0, 0.45, 1.0], id: \.self) { fraction in
                            Circle()
                                .fill(fraction <= journey.progressFraction ? Color.green : Color.white.opacity(0.3))
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
                                .offset(x: totalWidth * fraction - 6)
                        }

                        // Train icon
                        Image(systemName: "tram.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.orange)
                            .clipShape(Circle())
                            .shadow(color: .orange.opacity(0.6), radius: 6)
                            .offset(x: trainX - 13, y: -22)
                    }
                }
                .frame(height: 40)

                // Station codes below
                HStack {
                    Text(journey.origin.code)
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                    Spacer()
                    Text(journey.intermediate.code)
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                    Spacer()
                    Text(journey.destination.code)
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
        }
    }

    @ViewBuilder
    func stationTimeView(station: Station) -> some View {
        VStack(spacing: 2) {
            Text(station.scheduled)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
                .strikethrough(station.scheduled != station.actual, color: .red.opacity(0.7))
            Text(station.actual)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(station.scheduled == station.actual ? .green : .orange)
        }
    }
}

// MARK: - Congestion Card (Card A)

struct CongestionCard: View {
    let journey: Journey
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("ROOT CAUSE", systemImage: "waveform.path.ecg")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.45))
                        .tracking(1)
                    Spacer()
                    Text("\(journey.confidence)% CONFIDENCE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                }

                Text("CONGESTION AT\nRUGBY JUNCTION")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineSpacing(2)

                // Mini chart placeholder
                HStack(spacing: 4) {
                    ForEach([0.3, 0.5, 0.6, 0.8, 0.7, 0.9, 1.0, 0.85, 0.6, 0.4], id: \.self) { h in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(colors: [.orange.opacity(0.4), .orange],
                                               startPoint: .bottom, endPoint: .top)
                            )
                            .frame(width: 14, height: 50 * h)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 52)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HISTORICAL AVG")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                            .tracking(0.5)
                        Text("+\(journey.congestionAvgDelay)m")
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    Divider().frame(height: 30).background(Color.white.opacity(0.1))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AFFECTED SERVICES")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                            .tracking(0.5)
                        Text("3 of 4 Today")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
        }
    }
}

// MARK: - Rolling Stock Card (Card B)

struct RollingStockCard: View {
    let journey: Journey
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("EQUIPMENT PROFILE", systemImage: "train.side.front.car")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(1)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Unit: \(journey.trainUnit)")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                        Text("\(journey.trainType)\n(\(journey.trainCars) CARS)")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineSpacing(2)
                    }
                    Spacer()
                    Image(systemName: "tram.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(
                            LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.5)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                }

                Divider().background(Color.white.opacity(0.1))

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("INBOUND ARRIVAL DELAY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.45))
                            .tracking(0.5)
                        Spacer()
                        Text("+\(journey.inboundLateMinutes)m late")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    ProgressView(value: Double(journey.inboundLateMinutes), total: 30.0)
                        .tint(.orange)
                        .scaleEffect(x: 1, y: 1.6, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Connection Risk Card (Card C)

struct ConnectionRiskCard: View {
    let journey: Journey
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("EUSTON CONNECTION RISK", systemImage: "arrow.triangle.swap")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(1)

                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 52, height: 52)
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.green)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(journey.connectionRisk)
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundColor(.green)
                        Text(journey.connectionService)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                    Text("\(journey.transferMinutes) min transfer · Platforms nearby")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(10)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

// MARK: - Arrival Context Card

struct ArrivalContextCard: View {
    let journey: Journey
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                // Platform prediction
                VStack(alignment: .leading, spacing: 6) {
                    Label("PREDICTED PLATFORM", systemImage: "signpost.right.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.45))
                        .tracking(1)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(journey.platform)")
                            .font(.system(size: 56, weight: .black, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(colors: [.white, .white.opacity(0.7)],
                                               startPoint: .top, endPoint: .bottom)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(journey.platformProbability)%")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundColor(.green)
                            Text("Probability")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                }

                Divider().background(Color.white.opacity(0.1))

                // Delay Repay
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "sterlingsign.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.yellow)
                            Text("DELAY REPAY ELIGIBLE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.yellow)
                                .tracking(0.5)
                        }
                        Text("\(journey.delayMinutes)+ min delay · Avanti West Coast")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                    Button(action: {}) {
                        Text("CLAIM NOW")
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(colors: [.yellow, .orange],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .clipShape(Capsule())
                            .shadow(color: .orange.opacity(0.5), radius: 8, y: 3)
                    }
                }
                .padding(12)
                .background(Color.yellow.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.yellow.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }
}

// MARK: - Main Content View

struct ContentView: View {
    let journey = mockJourney

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(hue: 0.62, saturation: 0.3, brightness: 0.08),
                         Color(hue: 0.0, saturation: 0.0, brightness: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    // Nav Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("LPY → EUS")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Text("Tue 29 Jul · Avanti West Coast")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        Spacer()
                        Button(action: {}) {
                            Image(systemName: "bell.badge.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.orange)
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.top, 8)

                    StatusHeaderCard(journey: journey)
                    TimelineCard(journey: journey)

                    // Section header
                    HStack {
                        Text("PREDICTIVE INTELLIGENCE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.35))
                            .tracking(1.5)
                        Spacer()
                    }

                    CongestionCard(journey: journey)
                    RollingStockCard(journey: journey)
                    ConnectionRiskCard(journey: journey)

                    // Section header
                    HStack {
                        Text("ARRIVAL CONTEXT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.35))
                            .tracking(1.5)
                        Spacer()
                    }

                    ArrivalContextCard(journey: journey)

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 16)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
