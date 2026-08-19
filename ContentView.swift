import SwiftUI
import MapKit
import SwiftData



// MARK: - Adaptive Colour Helpers

/// Returns a colour that adapts based on the current colour scheme.
struct AdaptiveColor {
    let light: Color
    let dark: Color

    func resolve(in colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? dark : light
    }
}

// MARK: - App Brand Colour (Apple #1D1D1F)

/// Apple's canonical near-black — used everywhere instead of arbitrary navy or pure black.
extension Color {
    static let appleBlack    = Color(red: 29/255, green: 29/255, blue: 31/255)  // #1D1D1F
    // Keep these names so existing call-sites compile unchanged
    static let appBlue       = Color.appleBlack
    static let appBlueBright = Color.appleBlack
}

extension AdaptiveColor {
    // Background gradient — clean white in light mode
    static let bgTop    = AdaptiveColor(light: Color(red: 0.97, green: 0.97, blue: 0.97),
                                        dark:  Color(red: 0.03, green: 0.07, blue: 0.16))
    static let bgBottom = AdaptiveColor(light: Color(red: 1.0,  green: 1.0,  blue: 1.0),
                                        dark:  Color(red: 0.01, green: 0.03, blue: 0.09))

    // Card surface / stroke
    static let cardStroke = AdaptiveColor(light: Color.appleBlack.opacity(0.08),
                                          dark:  Color.white.opacity(0.08))

    // Primary text — Apple #1D1D1F
    static let primary = AdaptiveColor(light: Color.appleBlack,
                                       dark:  Color.white)

    // Secondary / muted text
    static let secondary = AdaptiveColor(light: Color.appleBlack.opacity(0.45),
                                         dark:  Color.white.opacity(0.50))

    static let tertiary  = AdaptiveColor(light: Color.appleBlack.opacity(0.30),
                                         dark:  Color.white.opacity(0.35))

    // Divider
    static let divider = AdaptiveColor(light: Color.appleBlack.opacity(0.08),
                                       dark:  Color.white.opacity(0.10))

    // Subtle fills
    static let subtleFill = AdaptiveColor(light: Color.appleBlack.opacity(0.04),
                                          dark:  Color.white.opacity(0.05))

    // Timeline track
    static let track = AdaptiveColor(light: Color.appleBlack.opacity(0.10),
                                     dark:  Color.white.opacity(0.12))

    // Station dot (unvisited)
    static let dotUnvisited = AdaptiveColor(light: Color.appleBlack.opacity(0.20),
                                            dark:  Color.white.opacity(0.30))

    // Station code text
    static let stationCode = AdaptiveColor(light: Color.appleBlack,
                                           dark:  Color.white)

    // Rolling stock icon gradient
    static let equipmentIconTop    = AdaptiveColor(light: Color.appleBlack.opacity(0.70),
                                                   dark:  Color.white.opacity(0.90))
    static let equipmentIconBottom = AdaptiveColor(light: Color.appleBlack.opacity(0.30),
                                                   dark:  Color.white.opacity(0.40))

    // Platform number gradient
    static let platformTop    = AdaptiveColor(light: Color.appleBlack,
                                              dark:  Color.white)
    static let platformBottom = AdaptiveColor(light: Color.appleBlack.opacity(0.45),
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
    let destination: TrainStation
    let scheduledDeparture: String
    let predictedArrival: String
    let actualArrival: String
    let delayMinutes: Int
    let platform: String
    let trainType: String
}

let mockJourney = TrainJourney(
    origin: TrainStation(code: "LPY", name: "Long Preston", scheduled: "11:00", actual: "11:00"),
    destination: TrainStation(code: "EUS", name: "London Euston", scheduled: "12:45", actual: "13:01"),
    scheduledDeparture: "11:00",
    predictedArrival: "13:01",
    actualArrival: "12:45",
    delayMinutes: 0,
    platform: "12",
    trainType: "AVANTI PENDOLINO"
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
            .background(Color(red: 1, green: 1, blue: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AdaptiveColor.cardStroke.resolve(in: colorScheme), lineWidth: 1)
            )
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
                                .foregroundColor(journey.delayMinutes > 0 ? .red : .green)
                            Text(journey.delayMinutes > 0 ? "\(journey.delayMinutes)M DELAY PREDICTED" : "ON TIME")
                                .font(.system(size: 24, weight: .black))
                                .foregroundColor(journey.delayMinutes > 0 ? .red : .green)
                        }
                        Text("SCHEDULED DEPARTURE: \(journey.scheduledDeparture)")
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
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                .strikethrough(station.scheduled != station.actual, color: Color.red.opacity(0.7))
            Text(station.actual)
                .font(.system(size: 13, weight: .bold))
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

                        Capsule()
                            .fill(Color.appleBlack.opacity(0.12))
                            .frame(width: w - seg1End, height: 5)
                            .offset(x: seg1End)

                        ForEach(0..<3) { i in
                            let fraction = timelineFractions[i]
                            Circle()
                                .fill(fraction <= CGFloat(journey.progressFraction)
                                      ? Color.green
                                      : AdaptiveColor.dotUnvisited.resolve(in: colorScheme))
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color.appleBlack.opacity(0.15), lineWidth: 1))
                                .offset(x: w * fraction - 6)
                        }

                        Image(systemName: "tram.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.appleBlack)
                            .clipShape(Circle())
                            .offset(x: trainX - 13, y: -22)
                    }
                }
                .frame(height: 40)

                HStack {
                    Text(journey.origin.code)
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(AdaptiveColor.stationCode.resolve(in: colorScheme))
                    Spacer()
                    Text(journey.intermediate.code)
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(AdaptiveColor.stationCode.resolve(in: colorScheme))
                    Spacer()
                    Text(journey.destination.code)
                        .font(.system(size: 13, weight: .black))
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
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                    .lineSpacing(2)

                HStack(spacing: 4) {
                    ForEach(0..<barHeights.count, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.appleBlack.opacity(0.12 + 0.08 * barHeights[i]))
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
                            .font(.system(size: 20, weight: .black))
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
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                        Text("\(journey.trainType)\n(\(journey.trainCars) CARS)")
                            .font(.system(size: 16, weight: .black))
                            .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                            .lineSpacing(2)
                    }
                    Spacer()
                    Image(systemName: "tram.fill")
                        .font(.system(size: 36))
                        .foregroundColor(AdaptiveColor.equipmentIconTop.resolve(in: colorScheme))
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
                            .font(.system(size: 12, weight: .bold))
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
                            .font(.system(size: 20, weight: .black))
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
                            .font(.system(size: 56, weight: .black))
                            .foregroundColor(AdaptiveColor.platformTop.resolve(in: colorScheme))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(journey.platformProbability)%")
                                .font(.system(size: 22, weight: .black))
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
                            .foregroundColor(Color.appleBlack)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.yellow)
                            .clipShape(Capsule())
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

// MARK: - Journey Dashboard View

struct JourneyDashboardView: View {
    @Environment(\.colorScheme) private var colorScheme

    let journey: TrainJourney
    var rawService: RTTAPIService? = nil

    var body: some View {
        ZStack {
            Color(red: 1, green: 1, blue: 1)
            .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    // Header row
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(journey.origin.code) → \(journey.destination.code)")
                                .font(.system(size: 22, weight: .black))
                                .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                            Text(journey.trainType)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                        }
                        Spacer()

                        HStack(spacing: 10) {
                            if let service = rawService {
                                Button(action: {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    LiveActivityManager.shared.startTracking(service: service)
                                }) {
                                    Image(systemName: "livephoto")
                                        .font(.system(size: 18))
                                        .foregroundColor(.red)
                                        .padding(10)
                                        .background(Color(red: 1, green: 1, blue: 1))
                                        .clipShape(Circle())
                                }
                            }
                            // Bell button
                            Button(action: {}) {
                                Image(systemName: "bell.badge.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.appBlue)
                                    .padding(10)
                                    .background(Color(red: 1, green: 1, blue: 1))
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(.top, 8)

                    StatusHeaderCard(journey: journey)
                    TimelineCard(journey: journey)

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
    }
}

#Preview {
    JourneyDashboardView(journey: mockJourney)
}

extension RTTAPIService {
    func toTrainJourney() -> TrainJourney {
        let originCode = userSearchOriginCRS ?? (originCRS.isEmpty ? "UNK" : originCRS)
        let destCode = userSearchDestinationCRS ?? (destinationCRS.isEmpty ? "UNK" : destinationCRS)
        
        let originStation = TrainStation(code: originCode, name: originCode, scheduled: scheduledDeparture, actual: realtimeDeparture)
        let destStation = TrainStation(code: destCode, name: destCode, scheduled: userSearchDestinationArrivalTime ?? scheduledDeparture, actual: userSearchDestinationArrivalTime ?? scheduledDeparture)
        
        return TrainJourney(
            origin: originStation,
            destination: destStation,
            scheduledDeparture: "\(scheduledDeparture) \(originCode)-\(destCode)",
            predictedArrival: userSearchDestinationArrivalTime ?? scheduledDeparture,
            actualArrival: userSearchDestinationArrivalTime ?? scheduledDeparture,
            delayMinutes: delayMinutes,
            platform: platform,
            trainType: atocName ?? "Unknown Service"
        )
    }
}

// MARK: - UITabBarController: Transparent Tab Content Backgrounds
// SwiftUI's TabView wraps each Tab's content in a UIHostingController.
// Those hosting controllers have opaque white/black UIView backgrounds by
// default, which covers the universal Map sitting behind the TabView.
// We can't override @objc methods on UIHostingController directly because it
// is a generic class. Instead we reach each child via its parent
// UITabBarController — which is concrete and allows @objc overrides.
extension UITabBarController {
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewControllers?.forEach { $0.view.backgroundColor = .clear }
    }
}

// MARK: - Map Toggle Button

struct MapToggleButton: View {
    @AppStorage("isSatelliteMap") private var isSatelliteMap: Bool = true
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation {
                        isSatelliteMap.toggle()
                    }
                } label: {
                    Image(systemName: isSatelliteMap ? "map" : "globe.americas.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                }
                .padding(.trailing, 16)
                .padding(.top, 8)
            }
            Spacer()
        }
    }
}

// MARK: - Profile Toggle Button

struct ProfileToggleButton: View {
    @Binding var showingProfile: Bool
    
    var body: some View {
        VStack {
            HStack {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showingProfile = true
                } label: {
                    Image(systemName: "person.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                }
                .padding(.leading, 16)
                .padding(.top, 8)
                Spacer()
            }
            Spacer()
        }
    }
}

// MARK: - Root ContentView

struct ContentView: View {
    @AppStorage("isSatelliteMap") private var isSatelliteMap: Bool = true
    
    @State private var selectedTab: Int = 0
    @State private var globalSheetDetent: SheetDetent = .peek
    @State private var showingProfile: Bool = false

    /// Single persistent camera state — never recreated on tab switch.
    @State private var cameraPosition: MapCameraPosition = .camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 52.8, longitude: -1.6),
            distance: 1_500_000,
            heading: 0,
            pitch: 0
        )
    )
    @State private var currentCamera: MapCamera? = nil

    @State private var selectedTrainId: UUID? = nil
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var isLoadingRoute: Bool = false
    @State private var routeCache: [UUID: [CLLocationCoordinate2D]] = [:]

    @Query(filter: #Predicate<SavedTrain> { $0.isPast == false }) private var mySavedTrains: [SavedTrain]
    @Environment(\.modelContext) private var modelContext
    
    private var liveServices: [RTTAPIService] {
        mySavedTrains.compactMap { $0.service }
    }

    @State private var cameraDistance: Double = 500000
    @State private var selectedStationCRS: String? = nil
    
    @State private var showingStationOptions = false
    @State private var showingDeparturesBoard = false
    @State private var selectedNonHighlightedStation: String? = nil

    private var highlightedStations: Set<String> {
        let bookedOrigins = Set(liveServices.map { $0.userSearchOriginCRS ?? $0.originCRS })
        let selectedDestinations: Set<String> = {
            guard let selected = selectedStationCRS else { return [] }
            let destinations = liveServices
                .filter { ($0.userSearchOriginCRS ?? $0.originCRS) == selected }
                .map { $0.userSearchDestinationCRS ?? $0.destinationCRS }
            return Set(destinations)
        }()
        return bookedOrigins.union(selectedDestinations)
    }

    private var highlightedUKStations: [UKStation] {
        let highlighted = highlightedStations
        return ukStations.filter { highlighted.contains($0.crs) }
    }
    
    private var visibleUnhighlightedUKStations: [UKStation] {
        guard cameraDistance < 15000 else { return [] }
        let highlighted = highlightedStations
        return ukStations.filter { !highlighted.contains($0.crs) }
    }

    @MapContentBuilder
    private var stationsMapContent: some MapContent {
        ForEach(highlightedUKStations) { station in
            Marker(station.crs, systemImage: "tram.fill", coordinate: station.coordinate)
                .tint(Color.appBlue)
                .tag(station.crs)
        }

        ForEach(visibleUnhighlightedUKStations) { station in
            Marker(station.crs, systemImage: "tram.fill", coordinate: station.coordinate)
                .tint(.white)
                .tag(station.crs)
        }

        if routeCoordinates.count > 1 {
            MapPolyline(coordinates: routeCoordinates)
                .stroke(Color.appBlue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
    }

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
                        stationsMapContent
                    }
                    .mapStyle(isSatelliteMap ? .hybrid(elevation: .realistic) : .standard(elevation: .realistic))
                    .ignoresSafeArea()
                    .onMapCameraChange(frequency: .onEnd) { context in
                        cameraDistance = context.camera.distance
                        currentCamera = context.camera
                    }
                    
                    MapToggleButton()
                    ProfileToggleButton(showingProfile: $showingProfile)

                    HomeSheetView(currentDetent: $globalSheetDetent, selectedTab: $selectedTab)
                }
                .onAppear {
                    checkPastTrains()
                }
                .onReceive(archiveTimer) { _ in
                    checkPastTrains()
                }
            }

            Tab("Past Trains", systemImage: "clock.arrow.circlepath", value: 1) {
                NavigationStack {
                    ZStack {
                        Map(position: $cameraPosition, selection: $selectedStationCRS) {
                            stationsMapContent
                        }
                        .mapStyle(isSatelliteMap ? .hybrid(elevation: .realistic) : .standard(elevation: .realistic))
                        .ignoresSafeArea()
                        .onMapCameraChange(frequency: .onEnd) { context in
                            cameraDistance = context.camera.distance
                            currentCamera = context.camera
                        }
                        
                        MapToggleButton()
                        ProfileToggleButton(showingProfile: $showingProfile)

                        PastTrainsSheetView(currentDetent: $globalSheetDetent)
                    }
                    .toolbar(.hidden, for: .navigationBar)
                }
            }

            Tab("Add Train", systemImage: "plus", value: 2) {
                ZStack {
                    Map(position: $cameraPosition, selection: $selectedStationCRS) {
                        stationsMapContent
                    }
                    .mapStyle(isSatelliteMap ? .hybrid(elevation: .realistic) : .standard(elevation: .realistic))
                    .ignoresSafeArea()
                    .onMapCameraChange(frequency: .onEnd) { context in
                        cameraDistance = context.camera.distance
                        currentCamera = context.camera
                    }
                    
                    MapToggleButton()
                    ProfileToggleButton(showingProfile: $showingProfile)

                    AddTrainSheetView(selectedTab: $selectedTab, currentDetent: $globalSheetDetent)
                }
            }
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
        }
        .onChange(of: selectedTab) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if let cam = currentCamera {
                cameraPosition = .camera(cam)
            }
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
    }
    /// Fires every 60 seconds to auto-archive trains that have arrived.
    private let archiveTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private func checkPastTrains() {
        let now = Date()
        let calendar = Calendar.current

        for train in mySavedTrains {
            guard let service = train.service else { continue }

            // --- Cancelled trains go straight to Rail History ---
            if service.isCancelledService {
                if !train.isPast {
                    train.isPast = true
                    train.movedToPastAt = now
                }
                continue
            }

            // --- Parse the real (with-delay) arrival time ---
            // Prefer the user-search destination realtime arrival, then scheduled arrival.
            let arrivalTimeString: String? =
                service.userSearchDestinationArrivalTime
                ?? service.userSearchDestinationScheduledArrivalTime

            guard let timeStr = arrivalTimeString, timeStr.count == 5,
                  let hour = Int(timeStr.prefix(2)),
                  let minute = Int(timeStr.suffix(2)) else {
                // No usable arrival time — fall back: archive if added > 4 hours ago
                if now.timeIntervalSince(train.addedAt) > 4 * 3600 && !train.isPast {
                    train.isPast = true
                    train.movedToPastAt = now
                }
                continue
            }

            // Build the base date using the run date if available, otherwise fallback to today
            var baseDate = now
            if let runDateString = service.scheduleMetadata?.departureDate {
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                if let runDate = df.date(from: runDateString) {
                    baseDate = runDate
                }
            }

            var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
            components.hour = hour
            components.minute = minute
            components.second = 0

            guard var arrivalDate = calendar.date(from: components) else { continue }

            if service.scheduleMetadata?.departureDate == nil {
                // If the arrival time is more than 12 hours in the future relative to now,
                // the service probably departed yesterday — shift back one day.
                if arrivalDate.timeIntervalSince(now) > 12 * 3600 {
                    arrivalDate = calendar.date(byAdding: .day, value: -1, to: arrivalDate) ?? arrivalDate
                }
            } else {
                // Check if arrival crossed midnight relative to scheduled departure
                let depTimeStr = service.scheduledDeparture
                if depTimeStr.count >= 5,
                   let depHour = Int(depTimeStr.prefix(2)) {
                    if hour < depHour && (depHour - hour) > 4 {
                        arrivalDate = calendar.date(byAdding: .day, value: 1, to: arrivalDate) ?? arrivalDate
                    }
                }
            }

            // Move to Rail History once the real arrival time has passed.
            if now >= arrivalDate && !train.isPast {
                train.isPast = true
                train.movedToPastAt = arrivalDate
            }
        }

        try? modelContext.save()
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
                Color(red: 1, green: 1, blue: 1)
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
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                        
                        Text(service.atocName ?? "Unknown Operator")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(service.scheduledDeparture)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                            .strikethrough(service.trainStatus != .onTime, color: .secondary)
                        
                        if service.trainStatus != .onTime {
                            Text(service.realtimeDeparture)
                                .font(.system(size: 16, weight: .bold))
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
