import SwiftUI
import MapKit

// MARK: - Theme Manager

enum AppTheme: String, CaseIterable {
    case light  = "light"
    case dark   = "dark"
    case system = "system"

    var label: String {
        switch self {
        case .light:  return "Light"
        case .dark:   return "Dark"
        case .system: return "Automatic"
        }
    }

    var icon: String {
        switch self {
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }

    /// The value passed to .preferredColorScheme(_:). nil means follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }
}

class ThemeManager: ObservableObject {
    @AppStorage("appTheme") var theme: AppTheme = .light
}

// MARK: - Adaptive Colour Helpers

/// Returns a colour that adapts based on the current colour scheme.
struct AdaptiveColor {
    let light: Color
    let dark: Color

    func resolve(in colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? dark : light
    }
}

// MARK: - App Brand Blue

/// The primary brand colour – a deep navy blue.
extension Color {
    static let appBlue      = Color(red: 0.05, green: 0.18, blue: 0.42)   // ~#0D2E6B
    static let appBlueBright = Color(red: 0.20, green: 0.45, blue: 0.85)  // lighter variant for gradients
}

extension AdaptiveColor {
    // Background gradient colours – navy-tinted in both modes
    static let bgTop    = AdaptiveColor(light: Color(red: 0.90, green: 0.93, blue: 0.98),
                                        dark:  Color(red: 0.03, green: 0.07, blue: 0.16))
    static let bgBottom = AdaptiveColor(light: Color(red: 0.83, green: 0.88, blue: 0.96),
                                        dark:  Color(red: 0.01, green: 0.03, blue: 0.09))

    // Card surface  / stroke
    static let cardStroke = AdaptiveColor(light: Color.black.opacity(0.06),
                                          dark:  Color.white.opacity(0.08))

    // Primary text
    static let primary = AdaptiveColor(light: Color(white: 0.08),
                                       dark:  Color.white)

    // Secondary / muted text
    static let secondary = AdaptiveColor(light: Color(white: 0.35),
                                         dark:  Color.white.opacity(0.50))

    static let tertiary  = AdaptiveColor(light: Color(white: 0.50),
                                         dark:  Color.white.opacity(0.35))

    // Divider
    static let divider = AdaptiveColor(light: Color.black.opacity(0.08),
                                       dark:  Color.white.opacity(0.10))

    // Subtle fills
    static let subtleFill = AdaptiveColor(light: Color.black.opacity(0.04),
                                          dark:  Color.white.opacity(0.05))

    // Timeline track
    static let track = AdaptiveColor(light: Color.black.opacity(0.10),
                                     dark:  Color.white.opacity(0.12))

    // Station dot (unvisited)
    static let dotUnvisited = AdaptiveColor(light: Color.black.opacity(0.20),
                                            dark:  Color.white.opacity(0.30))

    // Station code text
    static let stationCode = AdaptiveColor(light: Color(white: 0.12),
                                           dark:  Color.white)

    // Rolling stock icon gradient
    static let equipmentIconTop    = AdaptiveColor(light: Color.black.opacity(0.70),
                                                   dark:  Color.white.opacity(0.90))
    static let equipmentIconBottom = AdaptiveColor(light: Color.black.opacity(0.30),
                                                   dark:  Color.white.opacity(0.40))

    // Platform number gradient
    static let platformTop    = AdaptiveColor(light: Color(white: 0.10),
                                              dark:  Color.white)
    static let platformBottom = AdaptiveColor(light: Color(white: 0.35),
                                              dark:  Color.white.opacity(0.70))
}

// MARK: - Mock Data Models

struct TrainStation {
    let code: String
    let name: String
    let scheduled: String
    let actual: String
}

struct TrainJourney {
    let origin: TrainStation
    let intermediate: TrainStation
    let destination: TrainStation
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
    let transferMinutes: Int
    let congestionAvgDelay: Int
    let progressFraction: Double
}

let mockJourney = TrainJourney(
    origin: TrainStation(code: "LPY", name: "Long Preston", scheduled: "11:00", actual: "11:00"),
    intermediate: TrainStation(code: "RUG", name: "Rugby", scheduled: "11:52", actual: "11:58"),
    destination: TrainStation(code: "EUS", name: "London Euston", scheduled: "12:45", actual: "13:01"),
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
    transferMinutes: 5,
    congestionAvgDelay: 11,
    progressFraction: 0.72
)

// MARK: - Bar chart data

private let barHeights: [CGFloat] = [0.3, 0.5, 0.6, 0.8, 0.7, 0.9, 1.0, 0.85, 0.6, 0.4]
private let timelineFractions: [CGFloat] = [0.0, 0.45, 1.0]

// MARK: - Reusable Card Background

struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AdaptiveColor.cardStroke.resolve(in: colorScheme), lineWidth: 1)
            )
    }
}

// MARK: - Theme Toggle Button

struct ThemeToggleButton: View {
    @ObservedObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Menu {
            ForEach(AppTheme.allCases, id: \.self) { theme in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        themeManager.theme = theme
                    }
                } label: {
                    Label(theme.label, systemImage: theme.icon)
                }
                .disabled(themeManager.theme == theme)
            }
        } label: {
            Image(systemName: themeManager.theme.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
    }
}

// MARK: - Status Header Card

struct StatusHeaderCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let journey: TrainJourney

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "tram.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.appBlue)
                            Text("\(journey.delayMinutes)M DELAY PREDICTED")
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundColor(.appBlue)
                        }
                        Text("BASED ON INBOUND EQUIPMENT (\(journey.scheduledDeparture))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                            .tracking(0.5)
                    }
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Color.appBlue.opacity(0.15))
                            .frame(width: 52, height: 52)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.appBlue)
                    }
                }

                Divider().background(AdaptiveColor.divider.resolve(in: colorScheme))

                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .shadow(color: Color.green, radius: 3)
                    Text("ON TIME (per departure board)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                    Spacer()
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.appBlue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.appBlue.opacity(0.18))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - Station Time View

struct StationTimeView: View {
    @Environment(\.colorScheme) private var colorScheme
    let station: TrainStation

    var body: some View {
        VStack(spacing: 2) {
            Text(station.scheduled)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                .strikethrough(station.scheduled != station.actual, color: Color.red.opacity(0.7))
            Text(station.actual)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(station.scheduled == station.actual ? .green : .orange)
        }
    }
}

// MARK: - Dynamic Timeline Card

struct TimelineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let journey: TrainJourney

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("LIVE JOURNEY", systemImage: "location.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                    .tracking(1)

                HStack {
                    StationTimeView(station: journey.origin)
                    Spacer()
                    StationTimeView(station: journey.intermediate)
                    Spacer()
                    StationTimeView(station: journey.destination)
                }

                GeometryReader { geo in
                    let w = geo.size.width
                    let seg1End = w * 0.45
                    let trainX = w * journey.progressFraction

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AdaptiveColor.track.resolve(in: colorScheme))
                            .frame(height: 5)

                        Capsule()
                            .fill(Color.green)
                            .frame(width: seg1End, height: 5)

                        LinearGradient(
                            colors: [Color.green, Color.appBlue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .clipShape(Capsule())
                        .frame(width: w - seg1End, height: 5)
                        .offset(x: seg1End)

                        ForEach(0..<3) { i in
                            let fraction = timelineFractions[i]
                            Circle()
                                .fill(fraction <= CGFloat(journey.progressFraction)
                                      ? Color.green
                                      : AdaptiveColor.dotUnvisited.resolve(in: colorScheme))
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 1))
                                .offset(x: w * fraction - 6)
                        }

                        Image(systemName: "tram.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.appBlue)
                            .clipShape(Circle())
                            .shadow(color: Color.appBlue.opacity(0.6), radius: 6)
                            .offset(x: trainX - 13, y: -22)
                    }
                }
                .frame(height: 40)

                HStack {
                    Text(journey.origin.code)
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundColor(AdaptiveColor.stationCode.resolve(in: colorScheme))
                    Spacer()
                    Text(journey.intermediate.code)
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundColor(AdaptiveColor.stationCode.resolve(in: colorScheme))
                    Spacer()
                    Text(journey.destination.code)
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundColor(AdaptiveColor.stationCode.resolve(in: colorScheme))
                }
            }
        }
    }
}

// MARK: - Congestion Card (Card A)

struct CongestionCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let journey: TrainJourney

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("ROOT CAUSE", systemImage: "waveform.path.ecg")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                        .tracking(1)
                    Spacer()
                    Text("\(journey.confidence)% CONFIDENCE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.appBlue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.appBlue.opacity(0.15))
                        .clipShape(Capsule())
                }

                Text("CONGESTION AT\nRUGBY JUNCTION")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                    .lineSpacing(2)

                HStack(spacing: 4) {
                    ForEach(0..<barHeights.count, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [Color.appBlue.opacity(0.4), Color.appBlue],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 14, height: 50 * barHeights[i])
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 52)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HISTORICAL AVG")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                            .tracking(0.5)
                        Text("+\(journey.congestionAvgDelay)m")
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                            .foregroundColor(.appBlue)
                    }
                    Divider()
                        .frame(height: 30)
                        .background(AdaptiveColor.divider.resolve(in: colorScheme))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AFFECTED SERVICES")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                            .tracking(0.5)
                        Text("3 of 4 Today")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                    }
                }
            }
        }
    }
}

// MARK: - Rolling Stock Card (Card B)

struct RollingStockCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let journey: TrainJourney

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("EQUIPMENT PROFILE", systemImage: "tram.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                    .tracking(1)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Unit: \(journey.trainUnit)")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                        Text("\(journey.trainType)\n(\(journey.trainCars) CARS)")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                            .lineSpacing(2)
                    }
                    Spacer()
                    Image(systemName: "tram.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    AdaptiveColor.equipmentIconTop.resolve(in: colorScheme),
                                    AdaptiveColor.equipmentIconBottom.resolve(in: colorScheme)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                Divider().background(AdaptiveColor.divider.resolve(in: colorScheme))

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("INBOUND ARRIVAL DELAY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                            .tracking(0.5)
                        Spacer()
                        Text("+\(journey.inboundLateMinutes)m late")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.appBlue)
                    }
                    ProgressView(value: Double(journey.inboundLateMinutes), total: 30.0)
                        .tint(.appBlue)
                        .scaleEffect(x: 1, y: 1.6, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Connection Risk Card (Card C)

struct ConnectionRiskCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let journey: TrainJourney

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("EUSTON CONNECTION RISK", systemImage: "arrow.triangle.swap")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
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
                            .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 13))
                        .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                    Text("\(journey.transferMinutes) min transfer · Platforms nearby")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                }
                .padding(10)
                .background(AdaptiveColor.subtleFill.resolve(in: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

// MARK: - Arrival Context Card

struct ArrivalContextCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let journey: TrainJourney

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("PREDICTED PLATFORM", systemImage: "signpost.right.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                        .tracking(1)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(journey.platform)")
                            .font(.system(size: 56, weight: .black, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        AdaptiveColor.platformTop.resolve(in: colorScheme),
                                        AdaptiveColor.platformBottom.resolve(in: colorScheme)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(journey.platformProbability)%")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundColor(.green)
                            Text("Probability")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                        }
                    }
                }

                Divider().background(AdaptiveColor.divider.resolve(in: colorScheme))

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
                            .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                    }
                    Spacer()
                    Button(action: {}) {
                        Text("CLAIM NOW")
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: [Color.yellow, Color.yellow.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Capsule())
                            .shadow(color: Color.yellow.opacity(0.5), radius: 8, y: 3)
                    }
                }
                .padding(12)
                .background(Color.yellow.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.yellow.opacity(0.20), lineWidth: 1)
                )
            }
        }
    }
}

// MARK: - Sample Dashboard View

struct SampleDashboardView: View {
    @StateObject private var themeManager = ThemeManager()
    @Environment(\.colorScheme) private var colorScheme

    let journey = mockJourney

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

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    // Header row
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("LPY → EUS")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                            Text("Tue 29 Jul · Avanti West Coast")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                        }
                        Spacer()

                        HStack(spacing: 10) {
                            // Theme toggle
                            ThemeToggleButton(themeManager: themeManager)

                            // Bell button
                            Button(action: {}) {
                                Image(systemName: "bell.badge.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.appBlue)
                                    .padding(10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(.top, 8)

                    StatusHeaderCard(journey: journey)
                    TimelineCard(journey: journey)

                    HStack {
                        Text("PREDICTIVE INTELLIGENCE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                            .tracking(1.5)
                        Spacer()
                    }

                    CongestionCard(journey: journey)
                    RollingStockCard(journey: journey)
                    ConnectionRiskCard(journey: journey)

                    HStack {
                        Text("ARRIVAL CONTEXT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                            .tracking(1.5)
                        Spacer()
                    }

                    ArrivalContextCard(journey: journey)

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 16)
            }
        }
        .preferredColorScheme(themeManager.theme.colorScheme)
    }
}

#Preview {
    SampleDashboardView()
}

// MARK: - Root ContentView

struct ContentView: View {
    @State private var selectedTab: Int = 0
    @State private var showingAddTrain = false
    @StateObject private var themeManager = ThemeManager()

    /// Single persistent camera state — never recreated on tab switch.
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.8, longitude: -1.6),
            span: MKCoordinateSpan(latitudeDelta: 5.5, longitudeDelta: 5.5)
        )
    )

    @State private var selectedTrainId: UUID? = nil
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var isLoadingRoute: Bool = false
    @State private var routeCache: [UUID: [CLLocationCoordinate2D]] = [:]

    @State private var liveServices: [RTTAPIService] = []
    @State private var cameraDistance: Double = 500000
    @State private var selectedStationCRS: String? = nil
    
    @State private var showingStationOptions = false
    @State private var showingDeparturesBoard = false
    @State private var selectedNonHighlightedStation: String? = nil

    var body: some View {
        // ── iOS 26 liquid glass pattern ───────────────────────────────────
        // The Map lives *inside* the My Trains tab content, co-located with
        // the bottom sheet in a ZStack. This is exactly how Apple Maps works
        // on iOS 26: the liquid glass tab bar floats natively over the tab
        // content — no background-stripping tricks required.
        // Camera state lives here in ContentView so the map position is
        // preserved when the user switches tabs and comes back.
        TabView(selection: $selectedTab) {
            Tab("My Trains", systemImage: "tram.fill", value: 0) {
                ZStack {
                    Map(position: $cameraPosition, selection: $selectedStationCRS) {
                        let bookedOrigins = Set(liveServices.map { $0.userSearchOriginCRS ?? $0.originCRS })
                        let selectedDestinations: Set<String> = {
                            guard let selected = selectedStationCRS else { return [] }
                            let destinations = liveServices
                                .filter { ($0.userSearchOriginCRS ?? $0.originCRS) == selected }
                                .map { $0.userSearchDestinationCRS ?? $0.destinationCRS }
                            return Set(destinations)
                        }()
                        
                        let highlightedStations = bookedOrigins.union(selectedDestinations)

                        ForEach(Array(knownStationCoordinates.keys), id: \.self) { crs in
                            let isHighlighted = highlightedStations.contains(crs)
                            let isZoomedIn = cameraDistance < 15000

                            if (isHighlighted || isZoomedIn), let coord = knownStationCoordinates[crs] {
                                Marker(crs, systemImage: "tram.fill", coordinate: coord)
                                    .tint(isHighlighted ? Color.appBlue : Color.white)
                                    .tag(crs)
                            }
                        }

                        if routeCoordinates.count > 1 {
                            MapPolyline(coordinates: routeCoordinates)
                                .stroke(Color.appBlue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .ignoresSafeArea()
                    .onMapCameraChange(frequency: .onEnd) { context in
                        cameraDistance = context.camera.distance
                    }

                    HomeSheetView(liveServices: $liveServices)
                }
            }

            Tab("Past Trains", systemImage: "clock.arrow.circlepath", value: 1) {
                ZStack {
                    Map(position: $cameraPosition, selection: $selectedStationCRS) {
                        let bookedOrigins = Set(liveServices.map { $0.userSearchOriginCRS ?? $0.originCRS })
                        let selectedDestinations: Set<String> = {
                            guard let selected = selectedStationCRS else { return [] }
                            let destinations = liveServices
                                .filter { ($0.userSearchOriginCRS ?? $0.originCRS) == selected }
                                .map { $0.userSearchDestinationCRS ?? $0.destinationCRS }
                            return Set(destinations)
                        }()
                        
                        let highlightedStations = bookedOrigins.union(selectedDestinations)

                        ForEach(Array(knownStationCoordinates.keys), id: \.self) { crs in
                            let isHighlighted = highlightedStations.contains(crs)
                            let isZoomedIn = cameraDistance < 15000

                            if (isHighlighted || isZoomedIn), let coord = knownStationCoordinates[crs] {
                                Marker(crs, systemImage: "tram.fill", coordinate: coord)
                                    .tint(isHighlighted ? Color.appBlue : Color.white)
                                    .tag(crs)
                            }
                        }

                        if routeCoordinates.count > 1 {
                            MapPolyline(coordinates: routeCoordinates)
                                .stroke(Color.appBlue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .ignoresSafeArea()

                    PastTrainsSheetView()
                }
            }

            Tab("Add Train", systemImage: "plus", value: 2) {
                // Bounces back immediately — "Add Train" is a sheet, not a tab.
                // DispatchQueue defers the mutation past the render cycle to avoid
                // a 1-frame flash.
                Color.clear
                    .onAppear {
                        DispatchQueue.main.async {
                            selectedTab = 0
                            showingAddTrain = true
                        }
                    }
            }
        }
        .sheet(isPresented: $showingAddTrain) {
            AddTrainView(myTrains: $liveServices)
        }
        .onChange(of: selectedStationCRS) { _, newValue in
            guard let newValue = newValue else { return }
            
            let allMyStations = Set(liveServices.flatMap { [
                $0.userSearchOriginCRS ?? $0.originCRS,
                $0.userSearchDestinationCRS ?? $0.destinationCRS
            ] })
            
            if !allMyStations.contains(newValue) {
                selectedNonHighlightedStation = newValue
                showingStationOptions = true
            }
        }
        .confirmationDialog("Station Options", isPresented: $showingStationOptions, titleVisibility: .hidden) {
            Button("See Departures Board") {
                showingDeparturesBoard = true
            }
            Button("Cancel", role: .cancel) {
                selectedStationCRS = nil
                selectedNonHighlightedStation = nil
            }
        }
        .sheet(isPresented: $showingDeparturesBoard, onDismiss: {
            selectedStationCRS = nil
            selectedNonHighlightedStation = nil
        }) {
            if let crs = selectedNonHighlightedStation {
                DeparturesBoardView(crs: crs)
            }
        }
        .preferredColorScheme(themeManager.theme.colorScheme)
    }
}


#Preview {
    ContentView()
}


struct DeparturesBoardView: View {
    let crs: String
    
    @State private var allServices: [RTTServiceModel] = []
    @State private var displayedServices: [RTTServiceModel] = []
    @State private var displayLimit: Int = 10
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var stationName: String {
        ukStations.first { $0.crs == crs }?.name ?? crs
    }
    
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
                
                if isLoading {
                    ProgressView("Loading departures...")
                        .tint(.appBlue)
                } else if let errorMessage = errorMessage {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                            .padding(.bottom, 8)
                        Text("Failed to load")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                        Button("Retry") {
                            Task {
                                await loadData()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                } else if allServices.isEmpty {
                    VStack {
                        Image(systemName: "tram.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 8)
                        Text("No upcoming departures")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(displayedServices) { service in
                                DepartureServiceCard(service: service)
                            }
                            
                            if displayedServices.count < allServices.count {
                                Button(action: {
                                    withAnimation {
                                        displayLimit += 10
                                        displayedServices = Array(allServices.prefix(displayLimit))
                                    }
                                }) {
                                    Text("See More Trains +")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.appBlue)
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(GlassCard { Color.clear })
                                }
                                .padding(.top, 8)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("\(stationName) Departures")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadData()
            }
        }
    }
    
    private func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await RTTService.shared.departures(from: crs)
            let services = response.services ?? []
            allServices = services
            displayedServices = Array(allServices.prefix(displayLimit))
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct DepartureServiceCard: View {
    let service: RTTServiceModel
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.destinationName)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                        
                        Text(service.atocName ?? "Unknown Operator")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(service.scheduledDeparture)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                            .strikethrough(service.trainStatus != .onTime, color: .secondary)
                        
                        if service.trainStatus != .onTime {
                            Text(service.realtimeDeparture)
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundColor(service.trainStatus == .cancelled ? .red : .orange)
                        }
                    }
                }
                
                Divider().background(AdaptiveColor.divider.resolve(in: colorScheme))
                
                HStack {
                    HStack(spacing: 4) {
                        Text("Plat")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                        Text(service.platform)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                    }
                    
                    Spacer()
                    
                    Text(statusText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }
    
    private var statusText: String {
        switch service.trainStatus {
        case .onTime: return "ON TIME"
        case .delayed: return "DELAYED"
        case .cancelled: return "CANCELLED"
        case .arriving: return "ARRIVING"
        }
    }
    
    private var statusColor: Color {
        switch service.trainStatus {
        case .onTime: return .green
        case .delayed: return .orange
        case .cancelled: return .red
        case .arriving: return .blue
        }
    }
}
