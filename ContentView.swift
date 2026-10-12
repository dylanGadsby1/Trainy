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
    var isCancelled: Bool = false
    /// Only the timetable is known: no live feed is reporting on the train yet
    var isScheduledOnly: Bool = false
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

    private var headline: String {
        if journey.isCancelled { return "CANCELLED" }
        if journey.delayMinutes > 0 { return "\(journey.delayMinutes)M DELAY PREDICTED" }
        return journey.isScheduledOnly ? "SCHEDULED" : "ON TIME"
    }

    private var headlineColor: Color {
        if journey.isCancelled || journey.delayMinutes > 0 { return .red }
        return journey.isScheduledOnly ? TrainStatus.scheduled.color : .green
    }

    /// What the origin station's departure board currently shows for this train.
    private var boardStatus: (text: String, color: Color) {
        if journey.isCancelled { return ("CANCELLED", .red) }
        if journey.origin.scheduled != journey.origin.actual { return ("EXPECTED \(journey.origin.actual)", .orange) }
        return ("ON TIME", .green)
    }

    private var boardLine: String {
        journey.isScheduledOnly && !journey.isCancelled
            ? "TIMETABLE ONLY (not live yet)"
            : "\(boardStatus.text) (per departure board)"
    }

    private var boardLineColor: Color {
        journey.isScheduledOnly && !journey.isCancelled ? TrainStatus.scheduled.color : boardStatus.color
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "tram.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(headlineColor)
                            Text(headline)
                                .font(.system(size: 24, weight: .black))
                                .foregroundColor(headlineColor)
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
                        .fill(boardLineColor)
                        .frame(width: 8, height: 8)
                    Text(boardLine)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(boardLineColor)
                    Spacer()
                    Text(journey.isScheduledOnly ? "PLANNED" : "LIVE")
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
                    StationTimeView(station: journey.destination)
                }

                GeometryReader { geo in
                    let w = geo.size.width

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AdaptiveColor.track.resolve(in: colorScheme))
                            .frame(height: 5)

                        Circle()
                            .fill(Color.green)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.appleBlack.opacity(0.15), lineWidth: 1))
                            .offset(x: -6)

                        Circle()
                            .fill(AdaptiveColor.dotUnvisited.resolve(in: colorScheme))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.appleBlack.opacity(0.15), lineWidth: 1))
                            .offset(x: w - 6)
                    }
                }
                .frame(height: 12)
                .padding(.vertical, 8)

                HStack {
                    Text(journey.origin.code)
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

// MARK: - Calling Points Card

/// The stations on the user's journey with their live times, and where the train is among them.
struct CallingPointsCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let train: DarwinServiceAdapter

    var body: some View {
        GlassCard {
            // The train moves on between refreshes, so the card follows the clock
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                let stops = train.stops ?? []
                let passed = train.stopsPassed(at: timeline.date)

                VStack(alignment: .leading, spacing: 14) {
                    Label("CALLING POINTS", systemImage: "list.bullet")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                        .tracking(1)

                    if let position = train.position(at: timeline.date) {
                        HStack(spacing: 8) {
                            Image(systemName: "tram.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(5)
                                .background(train.trainStatus.color)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Between \(position.from.name) and \(position.to.name)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                                Text("Estimated from the train's times")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                            }
                        }
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                            CallingPointRow(
                                stop: stop,
                                place: index < passed ? .passed : (index == passed ? .next : .ahead),
                                isFirst: index == 0,
                                isLast: index == stops.count - 1,
                                color: train.trainStatus.color
                            )
                        }
                    }
                }
            }
        }
    }
}

struct CallingPointRow: View {
    /// Where a stop is relative to the train
    enum Place {
        case passed, next, ahead
    }

    @Environment(\.colorScheme) private var colorScheme
    let stop: DarwinServiceAdapter.Stop
    let place: Place
    let isFirst: Bool
    let isLast: Bool
    /// The colour of the part of the line already travelled
    let color: Color

    private var track: Color { AdaptiveColor.track.resolve(in: colorScheme) }

    var body: some View {
        HStack(spacing: 12) {
            // The line: travelled as far as the last stop the train left
            ZStack {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(isFirst ? .clear : (place == .passed ? color : track))
                    Rectangle()
                        .fill(isLast ? .clear : (place == .passed ? color : track))
                }
                .frame(width: 3)

                Circle()
                    .fill(place == .passed ? color : Color.white)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle().stroke(place == .ahead ? track : color, lineWidth: 2.5)
                    )
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(stop.name)
                    .font(.system(size: 14, weight: place == .next ? .black : .semibold))
                    .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                    .lineLimit(1)
                if stop.isCancelled {
                    Text("Not calling here")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.red)
                } else if place == .next {
                    Text(isFirst ? "Departs from here" : "Next stop")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(color)
                }
            }

            Spacer(minLength: 8)

            if !stop.isCancelled {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(stop.scheduled)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(stop.delayMinutes > 0 ? AdaptiveColor.tertiary.resolve(in: colorScheme) : AdaptiveColor.secondary.resolve(in: colorScheme))
                        .strikethrough(stop.delayMinutes > 0)
                    if stop.delayMinutes > 0 {
                        Text(stop.expected)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.orange)
                    }
                }
                .monospacedDigit()
            }
        }
        .frame(height: 44)
        .opacity(place == .passed ? 0.55 : 1)
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
                    Label("PLATFORM", systemImage: "signpost.right.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                        .tracking(1)

                    Text("\(journey.platform)")
                        .font(.system(size: 56, weight: .black))
                        .foregroundColor(AdaptiveColor.platformTop.resolve(in: colorScheme))
                }

                if journey.delayMinutes >= 15 {
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
                            Text("\(journey.delayMinutes)+ min delay · \(journey.trainType)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                        }
                        Spacer()
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
}

// MARK: - Journey Dashboard View

struct JourneyDashboardView: View {
    @Environment(\.colorScheme) private var colorScheme

    let journey: TrainJourney
    var rawService: DarwinServiceAdapter? = nil

    var body: some View {
        ZStack {
            Color(red: 1, green: 1, blue: 1)
            .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    // Header row
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(journey.trainType.uppercased())
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                                .tracking(1.5)
                            Text("\(journey.origin.code) → \(journey.destination.code)")
                                .font(.system(size: 22, weight: .black))
                                .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                        }
                        Spacer()

                        HStack(spacing: 10) {
                            if let service = rawService {
                                ShareLink(item: service.shareMessage()) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 18))
                                        .foregroundColor(.appBlue)
                                        .padding(10)
                                        .background(Color(red: 1, green: 1, blue: 1))
                                        .clipShape(Circle())
                                }
                                .accessibilityLabel("Share journey")

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
                    .padding(.top, 4)

                    StatusHeaderCard(journey: journey)
                    TimelineCard(journey: journey)

                    if let service = rawService, (service.stops?.count ?? 0) > 1 {
                        CallingPointsCard(train: service)
                    }

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
                .padding(.horizontal, 20)
            }
        }
    }
}

#Preview {
    JourneyDashboardView(journey: mockJourney)
}

extension DarwinServiceAdapter {
    func toTrainJourney() -> TrainJourney {
        let originCode = userSearchOriginCRS ?? (originCRS.isEmpty ? "UNK" : originCRS)
        let destCode = userSearchDestinationCRS ?? (destinationCRS.isEmpty ? "UNK" : destinationCRS)

        let scheduledArrival = userSearchDestinationScheduledArrivalTime ?? userSearchDestinationArrivalTime ?? "--:--"
        let expectedArrival = userSearchDestinationArrivalTime ?? scheduledArrival

        let originStation = TrainStation(code: originCode, name: originCode, scheduled: scheduledDeparture, actual: realtimeDeparture)
        let destStation = TrainStation(code: destCode, name: destCode, scheduled: scheduledArrival, actual: expectedArrival)

        return TrainJourney(
            origin: originStation,
            destination: destStation,
            scheduledDeparture: "\(scheduledDeparture) \(originCode)-\(destCode)",
            predictedArrival: expectedArrival,
            actualArrival: expectedArrival,
            delayMinutes: delayMinutes,
            platform: platform,
            trainType: atocName ?? "Unknown Service",
            isCancelled: isCancelledService,
            isScheduledOnly: isAwaitingLiveData == true
        )
    }
}

// MARK: - On the Map

extension DarwinServiceAdapter {
    /// The line to draw for the journey: through every stop whose location is known, or
    /// straight from origin to destination while the stops are not.
    var routeCoordinates: [CLLocationCoordinate2D] {
        let codes = stops?.map(\.crs)
            ?? [userSearchOriginCRS ?? originCRS, userSearchDestinationCRS ?? destinationCRS]
        return codes.compactMap { knownStationCoordinates[$0] }
    }

    /// The train's estimated place, on the straight line between the two stops it is between.
    func coordinate(at now: Date) -> CLLocationCoordinate2D? {
        guard let position = position(at: now),
              let from = knownStationCoordinates[position.from.crs],
              let to = knownStationCoordinates[position.to.crs] else { return nil }
        return CLLocationCoordinate2D(
            latitude: from.latitude + (to.latitude - from.latitude) * position.fraction,
            longitude: from.longitude + (to.longitude - from.longitude) * position.fraction
        )
    }
}

/// A saved train's estimated position on the map.
struct TrainPositionMarker: View {
    let color: Color

    var body: some View {
        Image(systemName: "tram.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.white)
            .padding(7)
            .background(color)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }
}

// MARK: - Sharing

extension DarwinServiceAdapter {
    /// The journey as it stands, in a sentence for someone who is waiting for the traveller.
    func shareMessage(at now: Date = Date()) -> String {
        func name(_ crs: String) -> String { ukStations.first { $0.crs == crs }?.name ?? crs }
        let origin = name(userSearchOriginCRS ?? originCRS)
        let destination = name(userSearchDestinationCRS ?? destinationCRS)

        // Name the day unless the train is today's, or is a few hours off just past midnight
        var day = ""
        if let date = scheduledDepartureDate, !Calendar.current.isDateInToday(date),
           date.timeIntervalSince(now) > 12 * 3600 {
            day = " on \(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))"
        }

        if isCancelledService {
            return "My \(scheduledDeparture) from \(origin) to \(destination)\(day) has been cancelled."
        }

        let hasLeft = (expectedDepartureDate ?? .distantFuture) <= now
        let opening = "\(hasLeft ? "I'm on" : "I'm getting") the \(scheduledDeparture) from \(origin)\(day)"
        guard let arrival = userSearchDestinationArrivalTime ?? userSearchDestinationScheduledArrivalTime else {
            return "\(opening) to \(destination)."
        }
        let lateness = delayMinutes > 0 ? " (running \(delayMinutes) min late)" : ""
        return "\(opening), due into \(destination) at \(arrival)\(lateness)."
    }
}

// MARK: - Floating Tab Bar

/// The system tab bar on its own, with no tab content behind it, so it can float over the
/// map and whichever sheet is showing. A SwiftUI TabView would bring a full-screen container
/// that covers the map and takes its touches; here anything that misses the bar falls through.
struct FloatingTabBar: UIViewRepresentable {
    struct Item {
        let title: String
        let systemImage: String
    }

    let items: [Item]
    @Binding var selection: Int
    /// Called when the tab that is already selected is tapped again
    var onReselect: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITabBar {
        let bar = PassthroughTabBar()
        bar.items = items.enumerated().map { index, item in
            UITabBarItem(title: item.title, image: UIImage(systemName: item.systemImage), tag: index)
        }
        bar.delegate = context.coordinator
        return bar
    }

    func updateUIView(_ bar: UITabBar, context: Context) {
        context.coordinator.parent = self
        bar.selectedItem = bar.items?.first { $0.tag == selection }
    }

    final class Coordinator: NSObject, UITabBarDelegate {
        var parent: FloatingTabBar
        init(_ parent: FloatingTabBar) { self.parent = parent }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            if parent.selection == item.tag {
                parent.onReselect()
            } else {
                parent.selection = item.tag
            }
        }
    }

    private final class PassthroughTabBar: UITabBar {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            let hit = super.hitTest(point, with: event)
            return hit === self ? nil : hit
        }
    }
}

// MARK: - Station Callout

/// A speech bubble that rises from a selected station on the map and opens its departures board.
struct StationCallout: View {
    /// Height of a selected map marker's balloon, which the bubble has to sit above
    static let markerClearance: CGFloat = 86

    let name: String
    let action: () -> Void

    private let pointerSize = CGSize(width: 18, height: 9)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text(name.uppercased())
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(Color.appleBlack.opacity(0.45))
                        .tracking(1)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("See departures board")
                            .font(.system(size: 14, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.appleBlack)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                // The bubble's tail, pointing down at the station
                Path { path in
                    path.move(to: .zero)
                    path.addLine(to: CGPoint(x: pointerSize.width, y: 0))
                    path.addLine(to: CGPoint(x: pointerSize.width / 2, y: pointerSize.height))
                    path.closeSubpath()
                }
                .fill(Color.white)
                .frame(width: pointerSize.width, height: pointerSize.height)
            }
            .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .fixedSize()
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
    @State private var globalSheetDetent: SheetDetent = .compact
    @State private var showingProfile: Bool = false
    /// The journey pushed from Past Trains, if any
    @State private var historyPath: [SavedTrain] = []

    /// Single persistent camera state — never recreated on tab switch.
    @State private var cameraPosition: MapCameraPosition = .camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 52.8, longitude: -1.6),
            distance: 1_500_000,
            heading: 0,
            pitch: 0
        )
    )

    /// The moment the trains' positions on the map were last worked out for
    @State private var positionClock = Date()

    @Query(filter: #Predicate<SavedTrain> { $0.isPast == false }) private var mySavedTrains: [SavedTrain]
    @Environment(\.modelContext) private var modelContext
    
    private var liveServices: [DarwinServiceAdapter] {
        mySavedTrains.compactMap { $0.service }
    }

    @Environment(\.scenePhase) private var scenePhase

    @State private var cameraDistance: Double = 500000
    /// The part of the map on screen, as of the last time the camera came to rest
    @State private var visibleRegion: MKCoordinateRegion? = nil
    @State private var selectedStationCRS: String? = nil
    
    @State private var showingDeparturesBoard = false
    /// The station whose departures board is open. Kept apart from the map selection,
    /// which the map clears by itself when the user taps elsewhere.
    @State private var departuresBoardCRS: String? = nil

    /// Stations show once the camera is closer than this, in metres
    private let stationVisibilityDistance: Double = 20_000

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
        guard cameraDistance < stationVisibilityDistance, let region = visibleRegion else { return [] }
        let highlighted = highlightedStations
        // A full span either side of the centre: what is on screen plus half a screen of
        // margin, so a station just past the edge is already there after a small pan
        let latitudes = (region.center.latitude - region.span.latitudeDelta)...(region.center.latitude + region.span.latitudeDelta)
        let longitudes = (region.center.longitude - region.span.longitudeDelta)...(region.center.longitude + region.span.longitudeDelta)
        return ukStations.filter {
            latitudes.contains($0.lat) && longitudes.contains($0.lon) && !highlighted.contains($0.crs)
        }
    }

    /// The selected station, when it is not part of one of the user's journeys: it gets a
    /// callout offering its departures board.
    private var calloutStation: UKStation? {
        guard let selected = selectedStationCRS else { return nil }
        let myStations = Set(liveServices.flatMap { [
            $0.userSearchOriginCRS ?? $0.originCRS,
            $0.userSearchDestinationCRS ?? $0.destinationCRS
        ] })
        guard !myStations.contains(selected) else { return nil }
        return ukStations.first { $0.crs == selected }
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

        if let station = calloutStation {
            Annotation("", coordinate: station.coordinate, anchor: .bottom) {
                StationCallout(name: station.name) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    departuresBoardCRS = station.crs
                    showingDeparturesBoard = true
                }
                // Clear the selected marker's balloon, which stands this tall above the station
                .padding(.bottom, StationCallout.markerClearance)
            }
            .annotationTitles(.hidden)
        }

        ForEach(liveServices.filter { $0.routeCoordinates.count > 1 }) { train in
            MapPolyline(coordinates: train.routeCoordinates)
                .stroke(Color.appBlue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }

        ForEach(liveServices) { train in
            if let coordinate = train.coordinate(at: positionClock) {
                Annotation("", coordinate: coordinate, anchor: .center) {
                    TrainPositionMarker(color: train.trainStatus.color)
                }
                .annotationTitles(.hidden)
            }
        }
    }

    var body: some View {
        // One Map for the whole app. It sits at the root and is never rebuilt, so switching
        // tab only swaps the sheet floating over it.
        ZStack {
            NavigationStack(path: $historyPath) {
                ZStack {
                    Map(position: $cameraPosition, selection: $selectedStationCRS) {
                        stationsMapContent
                    }
                    .mapStyle(isSatelliteMap ? .hybrid(elevation: .realistic) : .standard(elevation: .realistic))
                    .ignoresSafeArea()
                    .onMapCameraChange(frequency: .onEnd) { context in
                        cameraDistance = context.camera.distance
                        visibleRegion = context.region
                    }

                    MapToggleButton()
                    ProfileToggleButton(showingProfile: $showingProfile)

                    tabSheet(0) { HomeSheetView(currentDetent: $globalSheetDetent, selectedTab: $selectedTab) }
                    tabSheet(1) { PastTrainsSheetView(currentDetent: $globalSheetDetent) }
                    tabSheet(2) { AddTrainSheetView(selectedTab: $selectedTab, currentDetent: $globalSheetDetent) }
                }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: SavedTrain.self) { train in
                    RailHistoryDetailView(train: train)
                }
            }

            tabBar
        }
        .task {
            await TrainSync.shared.sync(in: modelContext)
        }
        .onReceive(refreshTimer) { _ in
            Task { await TrainSync.shared.sync(in: modelContext) }
        }
        .onReceive(positionTimer) { now in
            if !liveServices.isEmpty { positionClock = now }
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
        }
        .onChange(of: scenePhase) { _, phase in
            // Catch up as soon as the app comes back: a train may have come into Darwin's reach meanwhile
            if phase == .active {
                Task { await TrainSync.shared.sync(in: modelContext) }
            } else if phase == .background {
                BackgroundRefresh.schedule(in: modelContext.container)
            }
        }
        .onChange(of: selectedTab) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // A pushed journey belongs to Past Trains: don't leave it covering another tab
            historyPath.removeAll()
        }
        .sheet(isPresented: $showingDeparturesBoard, onDismiss: {
            selectedStationCRS = nil
            departuresBoardCRS = nil
        }) {
            if let crs = departuresBoardCRS {
                DeparturesBoardView(crs: crs)
            }
        }
    }

    /// Every tab's sheet stays mounted, so what it holds (a half-filled search, a scroll
    /// position) survives switching away. Only the selected one is shown and touchable.
    private func tabSheet<Content: View>(_ tab: Int, @ViewBuilder content: () -> Content) -> some View {
        content()
            // Swap instantly even when the tab changes inside an animation, so two
            // half-faded sheets never let the map show through
            .animation(nil) { $0.opacity(selectedTab == tab ? 1 : 0) }
            .allowsHitTesting(selectedTab == tab)
            .accessibilityHidden(selectedTab != tab)
    }

    private var tabBar: some View {
        GeometryReader { geo in
            FloatingTabBar(
                items: [
                    .init(title: "My Trains", systemImage: "tram.fill"),
                    .init(title: "Past Trains", systemImage: "clock.arrow.circlepath"),
                    .init(title: "Add Train", systemImage: "plus")
                ],
                selection: $selectedTab,
                // Same as the system: tapping the current tab again goes back to its root
                onReselect: { historyPath.removeAll() }
            )
            // UIKit's own tab bar height, plus the home indicator area it extends into
            .frame(height: 49 + geo.safeAreaInsets.bottom)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
        }
        // Stay put behind the keyboard rather than riding up on top of it
        .ignoresSafeArea(.keyboard)
    }

    /// Fires every 60 seconds so TrainSync can refresh live times and archive trains that have arrived.
    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// Moves the train markers along between refreshes.
    private let positionTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
}


#Preview {
    ContentView()
}


struct DeparturesBoardView: View {
    let crs: String
    
    @State private var allServices: [DarwinServiceModel] = []
    @State private var displayedServices: [DarwinServiceModel] = []
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
            let board = try await DarwinService.shared.departures(from: crs, numRows: 150)
            let services = board.trainServices ?? []
            allServices = services
            displayedServices = Array(allServices.prefix(displayLimit))
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct DepartureServiceCard: View {
    let service: DarwinServiceModel
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.destinationName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                        
                        Text(service.operator ?? "Unknown Operator")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(service.std ?? "N/A")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                            .strikethrough(service.status != .onTime, color: .secondary)
                        
                        if service.status != .onTime {
                            Text(service.etd ?? "N/A")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(service.status == .cancelled ? .red : .orange)
                        }
                    }
                }
                
                Divider().background(AdaptiveColor.divider.resolve(in: colorScheme))
                
                HStack {
                    HStack(spacing: 4) {
                        Text("Plat")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                        Text(service.platform ?? "TBC")
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
        switch service.status {
        case .onTime: return "ON TIME"
        case .delayed: return "DELAYED"
        case .cancelled: return "CANCELLED"
        }
    }
    
    private var statusColor: Color {
        switch service.status {
        case .onTime: return .green
        case .delayed: return .orange
        case .cancelled: return .red
        }
    }
}
