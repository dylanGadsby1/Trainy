import SwiftUI
import MapKit
import SwiftData



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
    /// Why the train is late or cancelled, when the feed says
    var reason: String? = nil
    var coaches: Int? = nil
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

// MARK: - Status Header Card

struct StatusHeaderCard: View {
    let journey: TrainJourney

    private var headline: String {
        if journey.isCancelled { return "Cancelled" }
        if journey.delayMinutes > 0 { return "\(journey.delayMinutes) min delay predicted" }
        return journey.isScheduledOnly ? "Scheduled" : "On time"
    }

    private var headlineColor: Color {
        if journey.isCancelled { return .statusCancelled }
        if journey.delayMinutes > 0 { return .statusDelayed }
        return journey.isScheduledOnly ? .statusScheduled : .statusOnTime
    }

    /// What the origin station's departure board currently shows for this train.
    private var boardStatus: (text: String, color: Color) {
        if journey.isCancelled { return ("Cancelled", .statusCancelled) }
        if journey.origin.scheduled != journey.origin.actual { return ("Expected \(journey.origin.actual)", .statusDelayed) }
        return ("On time", .statusOnTime)
    }

    private var boardLine: String {
        journey.isScheduledOnly && !journey.isCancelled
            ? "Timetable only (not live yet)"
            : "\(boardStatus.text) (per departure board)"
    }

    private var boardLineColor: Color {
        journey.isScheduledOnly && !journey.isCancelled ? .statusScheduled : boardStatus.color
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "tram.fill")
                                .font(.title3.weight(.semibold))
                                .accessibilityHidden(true)
                            Text(headline)
                                .font(.title2.weight(.bold))
                        }
                        .foregroundStyle(headlineColor)

                        Text("Scheduled departure: \(journey.scheduledDeparture)")
                            .font(.footnote)
                            .foregroundStyle(Color.inkSecondary)

                        if let reason = journey.reason {
                            Text(reason)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Color.subtleFill)
                            .frame(width: 52, height: 52)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.ink)
                    }
                    .accessibilityHidden(true)
                }

                Divider()

                HStack(spacing: 8) {
                    Circle()
                        .fill(boardLineColor)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(boardLine)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(boardLineColor)
                    Spacer()
                    StatusPill(journey.isScheduledOnly ? "Planned" : "Live", color: .ink)
                }
            }
        }
    }
}

// MARK: - Station Time View

struct StationTimeView: View {
    let station: TrainStation

    private var isRetimed: Bool { station.scheduled != station.actual }

    var body: some View {
        VStack(spacing: 2) {
            Text(station.scheduled)
                .font(.caption)
                .foregroundStyle(Color.inkSecondary)
                .strikethrough(isRetimed)
            Text(station.actual)
                .font(.footnote.weight(.bold))
                .foregroundStyle(isRetimed ? Color.statusDelayed : Color.statusOnTime)
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isRetimed ? "Expected \(station.actual), scheduled \(station.scheduled)" : station.actual)
    }
}

// MARK: - Dynamic Timeline Card

struct TimelineCard: View {
    let journey: TrainJourney

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("Live journey", systemImage: "location.fill")

                HStack {
                    StationTimeView(station: journey.origin)
                    Spacer()
                    StationTimeView(station: journey.destination)
                }

                GeometryReader { geo in
                    let w = geo.size.width

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.track)
                            .frame(height: 5)

                        Circle()
                            .fill(Color.statusOnTime)
                            .frame(width: 12, height: 12)
                            .offset(x: -6)

                        Circle()
                            .fill(Color.inkTertiary)
                            .frame(width: 12, height: 12)
                            .offset(x: w - 6)
                    }
                }
                .frame(height: 12)
                .padding(.vertical, 8)
                .accessibilityHidden(true)

                HStack {
                    Text(journey.origin.code)
                    Spacer()
                    Text(journey.destination.code)
                }
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color.ink)
                .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Calling Points Card

/// The stations on the user's journey with their live times, and where the train is among them.
struct CallingPointsCard: View {
    let train: DarwinServiceAdapter

    var body: some View {
        Card {
            // The train moves on between refreshes, so the card follows the clock
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                let stops = train.stops ?? []
                let passed = train.stopsPassed(at: timeline.date)

                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel("Calling points", systemImage: "list.bullet")

                    if let position = train.position(at: timeline.date) {
                        HStack(spacing: 8) {
                            Image(systemName: "tram.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(train.trainStatus.color, in: Circle())
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Between \(position.from.name) and \(position.to.name)")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Color.ink)
                                Text("Estimated from the train's times")
                                    .font(.caption)
                                    .foregroundStyle(Color.inkSecondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
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

    let stop: DarwinServiceAdapter.Stop
    let place: Place
    let isFirst: Bool
    let isLast: Bool
    /// The colour of the part of the line already travelled
    let color: Color

    private var note: String? {
        if stop.isCancelled { return "Not calling here" }
        if place == .next { return isFirst ? "Departs from here" : "Next stop" }
        return nil
    }

    private var spokenTime: String {
        if stop.isCancelled { return "" }
        return stop.delayMinutes > 0 ? "expected \(stop.expected), scheduled \(stop.scheduled)" : stop.scheduled
    }

    var body: some View {
        HStack(spacing: 12) {
            // The line: travelled as far as the last stop the train left
            ZStack {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(isFirst ? .clear : (place == .passed ? color : Color.track))
                    Rectangle()
                        .fill(isLast ? .clear : (place == .passed ? color : Color.track))
                }
                .frame(width: 3)

                Circle()
                    .fill(place == .passed ? color : Color.card)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle().stroke(place == .ahead ? Color.inkTertiary : color, lineWidth: 2.5)
                    )
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(stop.name)
                    .font(.subheadline.weight(place == .next ? .bold : .medium))
                    // A stop left behind steps back, but stays readable
                    .foregroundStyle(place == .passed ? Color.inkSecondary : Color.ink)
                if let note {
                    Text(note)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(stop.isCancelled ? Color.statusCancelled : color)
                }
            }
            .padding(.vertical, 6)

            Spacer(minLength: 8)

            if !stop.isCancelled {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(stop.scheduled)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.inkSecondary)
                        .strikethrough(stop.delayMinutes > 0)
                    if stop.delayMinutes > 0 {
                        Text(stop.expected)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Color.statusDelayed)
                    }
                }
                .monospacedDigit()
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([stop.name, note ?? (place == .passed ? "Passed" : ""), spokenTime].filter { !$0.isEmpty }.joined(separator: ", "))
    }
}

// MARK: - Arrival Context Card

struct ArrivalContextCard: View {
    let journey: TrainJourney

    @ScaledMetric(relativeTo: .largeTitle) private var platformSize: CGFloat = 56

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Platform", systemImage: "signpost.right.fill")

                        Text("\(journey.platform)")
                            .font(.system(size: platformSize, weight: .bold))
                            .foregroundStyle(Color.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)

                    if let coaches = journey.coaches {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel("Coaches", systemImage: "tram.fill")

                            Text("\(coaches)")
                                .font(.system(size: platformSize, weight: .bold))
                                .foregroundStyle(Color.ink)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }

                if journey.delayMinutes >= 15 {
                    Divider()

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "sterlingsign.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.ink)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delay Repay eligible")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.ink)
                            Text("\(journey.delayMinutes)+ min delay · \(journey.trainType)")
                                .font(.footnote)
                                .foregroundStyle(Color.inkSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(Color.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - Journey Dashboard View

struct JourneyDashboardView: View {
    let journey: TrainJourney
    var rawService: DarwinServiceAdapter? = nil
    /// Set when the train is a search result: the screen then offers to add it to My Trains
    var onAdd: (() -> Void)? = nil
    /// Where the user already has the search result ("In My Trains"), if they do
    var savedNote: String? = nil
    /// Set when the train is in My Trains: the screen then offers to remove it
    var onRemove: (() -> Void)? = nil
    /// Pushed onto a navigation stack with a bar above it, not shown as a sheet of its own
    var isPushed = false
    /// False when the screen was opened from the journey's own page, which already sets it out
    var showsJourney = true

    @State private var confirmingRemoval = false
    @Environment(\.dismiss) private var dismiss

    private var isSearchResult: Bool { onAdd != nil }

    var body: some View {
        ZStack {
            Color.surface
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    header
                        // As a sheet, clear of the drag indicator; pushed, the bar is above
                        .padding(.top, isSearchResult || isPushed ? 4 : 24)

                    StatusHeaderCard(journey: journey)

                    // Straight under the bad news, for a train the user is following
                    if onRemove != nil, let service = rawService, AlternativeTrains.areWorthOffering(for: service) {
                        AlternativeTrainsCard(train: service) {
                            // The train this screen shows is no longer followed
                            dismiss()
                        }
                    }

                    // The walk or ride at either end, for a train that came from a journey plan
                    if showsJourney, onRemove != nil, let service = rawService {
                        JourneyLegsCard(train: service)
                    }

                    TimelineCard(journey: journey)

                    if let service = rawService, (service.stops?.count ?? 0) > 1 {
                        CallingPointsCard(train: service)
                    }

                    SectionLabel("Arrival context")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)

                    ArrivalContextCard(journey: journey)

                    if let onRemove {
                        Button("Remove from My Trains", role: .destructive) {
                            confirmingRemoval = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .confirmationDialog("Remove this train from My Trains?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                            Button("Remove", role: .destructive, action: onRemove)
                        }
                    }

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let onAdd {
                Button(action: onAdd) {
                    Label(savedNote ?? "Add to My Trains", systemImage: savedNote == nil ? "plus" : "checkmark")
                }
                .buttonStyle(.primary)
                .disabled(savedNote != nil)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.surface)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(journey.trainType)
                Text("\(journey.origin.code) → \(journey.destination.code)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.ink)
                    .accessibilityLabel("\(UKStation.name(for: journey.origin.code)) to \(UKStation.name(for: journey.destination.code))")
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()

            HStack(spacing: 10) {
                if let service = rawService {
                    ShareLink(item: service.shareMessage()) {
                        Label("Share journey", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.icon)

                    // A Live Activity follows a saved train, so a search result has to be added first
                    if !isSearchResult {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            LiveActivityManager.shared.startTracking(service: service)
                        } label: {
                            Label("Start Live Activity", systemImage: "livephoto")
                        }
                        .buttonStyle(.icon)
                    }
                }
                if !isSearchResult {
                    // Bell button
                    Button(action: {}) {
                        Label("Alerts", systemImage: "bell.badge.fill")
                    }
                    .buttonStyle(.icon)
                }
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
            isScheduledOnly: isAwaitingLiveData == true,
            reason: disruptionReason,
            coaches: coaches
        )
    }
}

// MARK: - On the Map

extension DarwinServiceAdapter {
    /// The line to draw for the journey: along the tracks once the planner has supplied
    /// the train's path, and until then through every stop whose location is known, or
    /// straight from origin to destination while the stops are not.
    var routeCoordinates: [CLLocationCoordinate2D] {
        if let routeLine {
            let line = RouteLine.line(routeLine).coordinates
            if line.count > 1 { return line }
        }
        let codes = stops?.map(\.crs)
            ?? [userSearchOriginCRS ?? originCRS, userSearchDestinationCRS ?? destinationCRS]
        return codes.compactMap { knownStationCoordinates[$0] }
    }

    /// The journey's line at one moment, in two parts.
    struct RouteProgress {
        /// What the train has covered, as far as where it is now
        var travelled: [CLLocationCoordinate2D]
        /// What it has still to cover
        var ahead: [CLLocationCoordinate2D]
        /// Where the train is thought to be, while it is on its way
        var train: CLLocationCoordinate2D?
    }

    /// The journey's line at `now`, divided where the train is. The place is an estimate,
    /// worked out from the train's expected times between the two stops it is between.
    func routeProgress(at now: Date) -> RouteProgress {
        let route = routeCoordinates
        guard route.count > 1, !isCancelledService else {
            return RouteProgress(travelled: [], ahead: route, train: nil)
        }
        if hasArrived == true || (expectedArrivalDate.map { $0 <= now } ?? false) {
            return RouteProgress(travelled: route, ahead: [], train: nil)
        }
        guard let departure = expectedDepartureDate, departure <= now else {
            return RouteProgress(travelled: [], ahead: route, train: nil)
        }

        // Along the tracks: between the two stops by the clock, measured along the line
        if let routeLine, case let line = RouteLine.line(routeLine), line.coordinates.count > 1 {
            var distance = line.length * progress(at: now)
            if let position = position(at: now),
               let from = knownStationCoordinates[position.from.crs],
               let to = knownStationCoordinates[position.to.crs] {
                let start = line.distance(nearestTo: from)
                let end = line.distance(nearestTo: to, from: start)
                distance = start + (end - start) * position.fraction
            }
            if let parts = line.divided(at: distance) {
                return RouteProgress(travelled: parts.behind, ahead: parts.ahead, train: parts.point)
            }
        }

        if let position = position(at: now), let stops,
           let fromIndex = stops.firstIndex(where: { $0.id == position.from.id }),
           let toIndex = stops.firstIndex(where: { $0.id == position.to.id }),
           let from = knownStationCoordinates[position.from.crs],
           let to = knownStationCoordinates[position.to.crs] {
            let train = CLLocationCoordinate2D(
                latitude: from.latitude + (to.latitude - from.latitude) * position.fraction,
                longitude: from.longitude + (to.longitude - from.longitude) * position.fraction
            )
            return RouteProgress(
                travelled: stops[...fromIndex].compactMap { knownStationCoordinates[$0.crs] } + [train],
                ahead: [train] + stops[toIndex...].compactMap { knownStationCoordinates[$0.crs] },
                train: train
            )
        }

        // The stops, or where they are, are not known: go by the clock along the line
        return Self.divide(route, at: progress(at: now))
    }

    /// `route` divided at `fraction` of its length.
    private static func divide(_ route: [CLLocationCoordinate2D], at fraction: Double) -> RouteProgress {
        let lengths = zip(route, route.dropFirst()).map { start, end in
            CLLocation(latitude: start.latitude, longitude: start.longitude)
                .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
        }
        var left = lengths.reduce(0, +) * min(1, max(0, fraction))

        for (index, length) in lengths.enumerated() where length > 0 {
            if left <= length {
                let part = left / length
                let start = route[index], end = route[index + 1]
                let train = CLLocationCoordinate2D(
                    latitude: start.latitude + (end.latitude - start.latitude) * part,
                    longitude: start.longitude + (end.longitude - start.longitude) * part
                )
                return RouteProgress(
                    travelled: Array(route[...index]) + [train],
                    ahead: [train] + Array(route[(index + 1)...]),
                    train: train
                )
            }
            left -= length
        }
        return RouteProgress(travelled: route, ahead: [], train: nil)
    }
}

/// A saved train's estimated position on the map: a dot in the train's status colour with
/// a slow pulse round it, so it reads as live and is not taken for a station.
struct TrainPositionMarker: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: 26, height: 26)
                .scaleEffect(isPulsing ? 1.9 : 1)
                .opacity(isPulsing ? 0 : 1)

            Image(systemName: "train.side.front.car")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(color, in: Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
        .accessibilityLabel("Your train")
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

        // The sentence is right when it is sent; the link stays right afterwards
        let link = liveTrackingURL.map { "\nFollow it live: \($0.absoluteString)" } ?? ""

        let hasLeft = (expectedDepartureDate ?? .distantFuture) <= now
        let opening = "\(hasLeft ? "I'm on" : "I'm getting") the \(scheduledDeparture) from \(origin)\(day)"
        guard let arrival = userSearchDestinationArrivalTime ?? userSearchDestinationScheduledArrivalTime else {
            return "\(opening) to \(destination).\(link)"
        }
        let lateness = delayMinutes > 0 ? " (running \(delayMinutes) min late)" : ""
        return "\(opening), due into \(destination) at \(arrival)\(lateness).\(link)"
    }

    /// The train's public page on Realtime Trains, where anyone can follow it without the
    /// app. Nil until the train's identity there is known.
    var liveTrackingURL: URL? {
        // "gb-nr:Y80917:2026-10-12" is served at /service/gb-nr:Y80917/2026-10-12
        guard let parts = rttIdentity?.split(separator: ":"), parts.count == 3 else { return nil }
        return URL(string: "https://www.realtimetrains.co.uk/service/\(parts[0]):\(parts[1])/\(parts[2])")
    }
}

// MARK: - Describing a Train

extension DarwinServiceAdapter {
    /// The scheduled time from the user's origin to their destination, such as "2h 13m".
    var durationText: String? {
        guard let departure = DarwinTime.minutes(scheduledDeparture),
              let arrival = DarwinTime.minutes(userSearchDestinationScheduledArrivalTime ?? userSearchDestinationArrivalTime) else { return nil }
        let minutes = (arrival - departure + 1440) % 1440
        guard minutes > 0 else { return nil }
        if minutes < 60 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    /// The day the train leaves, when that is not today: "Tomorrow", or "Fri 16 Oct".
    /// A commute's train is followed from the evening before, so its card has to say.
    func dayLabel(at now: Date = Date()) -> String? {
        let calendar = Calendar.current
        guard let departure = scheduledDepartureDate, !calendar.isDate(departure, inSameDayAs: now) else { return nil }
        if calendar.isDateInTomorrow(departure) { return "Tomorrow" }
        return departure.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// The train in one sentence, for VoiceOver: a card's codes and struck-through times
    /// make little sense read out one by one.
    var spokenSummary: String {
        let origin = UKStation.name(for: userSearchOriginCRS ?? originCRS)
        let destination = UKStation.name(for: userSearchDestinationCRS ?? destinationCRS)

        var parts = ["\(origin) to \(destination)"]
        if let day = dayLabel() { parts.append(day) }
        parts.append(departureDelayMinutes > 0
            ? "departs \(realtimeDeparture), scheduled \(scheduledDeparture)"
            : "departs \(scheduledDeparture)")
        if let arrival = userSearchDestinationArrivalTime ?? userSearchDestinationScheduledArrivalTime {
            parts.append("arrives \(arrival)")
        }
        parts.append(trainStatus.label)
        parts.append(platform == "TBC" ? "platform to be confirmed" : "platform \(platform)")
        return parts.joined(separator: ", ")
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
        bar.tintColor = UIColor(Color.brand)
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
                // The bubble is white in both colour schemes, like the map's own callouts
                VStack(spacing: 2) {
                    Text(name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appleBlack.opacity(0.65))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("See departures board")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Color.appleBlack)
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
                .accessibilityLabel(isSatelliteMap ? "Show standard map" : "Show satellite map")
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
                .accessibilityLabel("Profile")
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
    @State private var myTrainsPeekHeight: CGFloat = 0
    @State private var showingProfile: Bool = false
    @State private var showingAddTrain: Bool = false
    /// The search being filled in, kept here so closing Add Train does not lose it
    @State private var searchDraft = TrainSearchDraft()
    /// What is pushed from Rail History, if anything: a journey, or the stats
    @State private var historyPath = NavigationPath()

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

    /// Past trains too: on a journey of several trains, the ones already done stay on the map
    @Query private var allSavedTrains: [SavedTrain]

    /// The trains drawn on the map: each one still to run, and the trains already done on
    /// a journey that is not over yet.
    private var mapServices: [DarwinServiceAdapter] {
        allSavedTrains.travelItems(past: false).flatMap(\.legs).compactMap(\.service)
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

    /// The stations of the user's journeys: where each train is boarded and where it is
    /// left, so a journey's start, its changes and its end.
    private var highlightedStations: Set<String> {
        Set(mapServices.flatMap { [
            $0.userSearchOriginCRS ?? $0.originCRS,
            $0.userSearchDestinationCRS ?? $0.destinationCRS
        ] })
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
        guard let selected = selectedStationCRS, !highlightedStations.contains(selected) else { return nil }
        return ukStations.first { $0.crs == selected }
    }

    @MapContentBuilder
    private var stationsMapContent: some MapContent {
        ForEach(highlightedUKStations) { station in
            Marker(station.crs, systemImage: "tram.fill", coordinate: station.coordinate)
                .tint(Color.appleBlack)
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
                    departuresBoardCRS = station.crs
                    showingDeparturesBoard = true
                }
                // Clear the selected marker's balloon, which stands this tall above the station
                .padding(.bottom, StationCallout.markerClearance)
            }
            .annotationTitles(.hidden)
        }

        // Each journey's line: grey where the train has still to go, dark where it has been
        ForEach(mapServices) { train in
            let route = train.routeProgress(at: positionClock)
            if route.ahead.count > 1 {
                MapPolyline(coordinates: route.ahead)
                    .stroke(Color.routeAhead, style: Self.routeStroke)
            }
            if route.travelled.count > 1 {
                MapPolyline(coordinates: route.travelled)
                    .stroke(Color.appleBlack, style: Self.routeStroke)
            }
        }

        // Where each train is now, where the dark line ends
        ForEach(mapServices) { train in
            if let coordinate = train.routeProgress(at: positionClock).train {
                Annotation("", coordinate: coordinate, anchor: .center) {
                    TrainPositionMarker(color: train.trainStatus.color)
                }
                .annotationTitles(.hidden)
            }
        }
    }

    private static let routeStroke = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)

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

                    tabSheet(0) { HomeSheetView(currentDetent: $globalSheetDetent, peekHeight: $myTrainsPeekHeight) { showingAddTrain = true } }
                    tabSheet(1) { PastTrainsSheetView(currentDetent: $globalSheetDetent, myTrainsPeekHeight: myTrainsPeekHeight) }
                }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: SavedTrain.self) { train in
                    RailHistoryDetailView(train: train)
                }
                .navigationDestination(for: RailStatsRoute.self) { _ in
                    RailStatsView()
                }
                .navigationDestination(for: JourneyRoute.self) { journey in
                    JourneyDetailView(journeyID: journey.id, isHistory: true)
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
        // A train just added gets its live times, and its path on the map, without waiting for the timer
        .onChange(of: mySavedTrains.count) { old, new in
            if new > old {
                Task { await TrainSync.shared.sync(in: modelContext) }
            } else {
                // A removed train's reminders go now, not at the next sync, in case the app is closed first
                Task {
                    await TrainAlerts.shared.refreshDepartureReminders(in: modelContext)
                    await TrainAlerts.shared.refreshApproachReminders(in: modelContext)
                }
            }
        }
        .onReceive(positionTimer) { now in
            if !liveServices.isEmpty { positionClock = now }
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
        }
        .sheet(isPresented: $showingAddTrain) {
            AddTrainView(draft: $searchDraft)
        }
        .onChange(of: scenePhase) { _, phase in
            // Catch up as soon as the app comes back: a train may have come into Darwin's reach meanwhile
            if phase == .active {
                Task { await TrainSync.shared.sync(in: modelContext) }
            } else if phase == .background {
                BackgroundRefresh.schedule(in: modelContext.container)
            }
        }
        .onChange(of: selectedTab) {
            // A pushed page belongs to Rail History: don't leave it covering another tab
            historyPath = NavigationPath()
        }
        .sheet(isPresented: $showingDeparturesBoard, onDismiss: {
            selectedStationCRS = nil
            departuresBoardCRS = nil
        }) {
            if let crs = departuresBoardCRS {
                DeparturesBoardView(crs: crs)
            }
        }
        // Text follows the user's size setting. The largest sizes are held back, because
        // the train cards set times side by side and stop fitting beyond this.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
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
                    .init(title: "Rail History", systemImage: "clock.arrow.circlepath")
                ],
                selection: $selectedTab,
                // Same as the system: tapping the current tab again goes back to its root
                onReselect: { historyPath = NavigationPath() }
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

    var stationName: String {
        UKStation.name(for: crs)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface
                    .ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading departures…")
                } else if let errorMessage = errorMessage {
                    ContentUnavailableView {
                        Label("Couldn't Load Departures", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try Again") {
                            Task {
                                await loadData()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                } else if allServices.isEmpty {
                    ContentUnavailableView("No Upcoming Departures", systemImage: "tram.fill")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(displayedServices) { service in
                                DepartureServiceCard(service: service)
                            }

                            if displayedServices.count < allServices.count {
                                Button("Show more trains") {
                                    withAnimation {
                                        displayLimit += 10
                                        displayedServices = Array(allServices.prefix(displayLimit))
                                    }
                                }
                                .buttonStyle(.secondary)
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
            errorMessage = TrainSearch.message(for: error)
        }
        isLoading = false
    }
}

struct DepartureServiceCard: View {
    let service: DarwinServiceModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.destinationName)
                            .font(.headline)
                            .foregroundStyle(Color.ink)

                        Text(service.operator ?? "Unknown operator")
                            .font(.footnote)
                            .foregroundStyle(Color.inkSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(service.std ?? "N/A")
                            .font(.headline)
                            .foregroundStyle(service.status == .onTime ? Color.ink : Color.inkSecondary)
                            .strikethrough(service.status != .onTime)

                        if service.status != .onTime {
                            Text(service.etd ?? "N/A")
                                .font(.callout.weight(.bold))
                                .foregroundStyle(statusColor)
                        }
                    }
                    .monospacedDigit()
                }

                Divider()

                HStack {
                    HStack(spacing: 4) {
                        Text("Platform")
                            .font(.footnote)
                            .foregroundStyle(Color.inkSecondary)
                        Text(service.platform ?? "TBC")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.ink)
                    }

                    Spacer()

                    StatusPill(statusText, color: statusColor)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        switch service.status {
        case .onTime: return "On time"
        case .delayed: return "Delayed"
        case .cancelled: return "Cancelled"
        }
    }

    private var statusColor: Color {
        switch service.status {
        case .onTime: return .statusOnTime
        case .delayed: return .statusDelayed
        case .cancelled: return .statusCancelled
        }
    }
}
