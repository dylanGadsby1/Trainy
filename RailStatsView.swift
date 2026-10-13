import SwiftUI
import SwiftData
import Charts
import CoreLocation

// MARK: - Travel Stats

/// What the Rail History adds up to.
struct TravelStats {
    /// Journeys that ran. A cancelled train was not travelled on.
    var journeys = 0
    var cancelled = 0
    var onTime = 0
    /// Minutes late, added up over every journey that ran
    var delayedMinutes = 0
    var longestDelay = 0
    var miles = 0
    /// Scheduled time on trains, plus how late each one was
    var minutesTravelled = 0

    // Delay Repay
    var openClaims = 0
    var claimed = 0
    var missedClaims = 0

    /// The pairs of stations travelled between, most journeys first. Both directions count as one route.
    var routes: [Route] = []
    /// The operators travelled with, most journeys first
    var operators: [Operator] = []
    /// Journeys that ran in each of the last six months, oldest first
    var months: [Month] = []

    struct Route: Identifiable {
        let first: String
        let second: String
        var journeys = 0

        var id: String { first + second }
        var name: String { "\(UKStation.name(for: first)) – \(UKStation.name(for: second))" }
    }

    struct Operator: Identifiable {
        let code: String?
        let name: String
        var journeys = 0
        var onTime = 0

        var id: String { code ?? name }
        var onTimeText: String { TravelStats.percent(onTime, of: journeys) }
    }

    struct Month: Identifiable {
        let start: Date
        var journeys = 0

        var id: Date { start }
        var name: String { start.formatted(.dateTime.month(.wide)) }
    }

    /// - Parameter trains: Every saved train. Only what has finished is counted.
    init(_ trains: [SavedTrain], now: Date = Date()) {
        let calendar = Calendar.current
        var metres = 0.0
        var routes: [String: Route] = [:]
        var operators: [String: Operator] = [:]

        let thisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        months = (0..<6).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: thisMonth) }.map { Month(start: $0) }

        // A journey of several trains counts once, and is judged by when its last train got in
        for item in trains.travelItems(past: true) {
            // One claim for a journey of several trains, by how late it ended
            for claim in item.claims.map(\.claim) {
                if claim.claimedAt != nil {
                    claimed += 1
                } else if claim.isOpen {
                    openClaims += 1
                } else {
                    missedClaims += 1
                }
            }

            let services = item.legs.compactMap(\.service)
            guard let first = services.first, let last = services.last else { continue }
            guard !services.contains(where: \.isCancelledService) else {
                cancelled += 1
                continue
            }

            // Against the journey as first planned, so a missed change counts for what it cost
            let late = item.minutesLate
            journeys += 1
            if late == 0 { onTime += 1 }
            delayedMinutes += late
            longestDelay = max(longestDelay, late)

            // Distance, time on board and the operator are each train's own
            for service in services {
                if let from = knownStationCoordinates[service.userSearchOriginCRS ?? service.originCRS],
                   let to = knownStationCoordinates[service.userSearchDestinationCRS ?? service.destinationCRS] {
                    metres += CLLocation(latitude: from.latitude, longitude: from.longitude)
                        .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
                }

                if let departure = DarwinTime.minutes(service.scheduledDeparture),
                   let arrival = DarwinTime.minutes(service.userSearchDestinationScheduledArrivalTime ?? service.userSearchDestinationArrivalTime) {
                    minutesTravelled += (arrival - departure + 1440) % 1440 + service.delayMinutes
                }

                let operatorName = OperatorBrand.from(code: service.atocCode)?.shortName ?? service.atocName ?? "Unknown"
                let operatorKey = service.atocCode ?? operatorName
                operators[operatorKey, default: Operator(code: service.atocCode, name: operatorName)].journeys += 1
                if service.delayMinutes == 0 { operators[operatorKey]?.onTime += 1 }
            }

            let ends = [first.userSearchOriginCRS ?? first.originCRS, last.userSearchDestinationCRS ?? last.destinationCRS].sorted()
            routes[ends.joined(), default: Route(first: ends[0], second: ends[1])].journeys += 1

            if let month = months.firstIndex(where: { calendar.isDate($0.start, equalTo: item.finishedAt, toGranularity: .month) }) {
                months[month].journeys += 1
            }
        }

        miles = Int((metres / 1609.344).rounded())
        self.routes = routes.values.sorted { ($0.journeys, $1.name) > ($1.journeys, $0.name) }
        self.operators = operators.values.sorted { ($0.journeys, $1.name) > ($1.journeys, $0.name) }
    }

    var onTimeText: String { Self.percent(onTime, of: journeys) }

    /// The average lateness of the journeys that were late at all
    var averageDelay: Int? {
        let late = journeys - onTime
        return late > 0 ? Int((Double(delayedMinutes) / Double(late)).rounded()) : nil
    }

    static func percent(_ part: Int, of whole: Int) -> String {
        guard whole > 0 else { return "–" }
        return (Double(part) / Double(whole)).formatted(.percent.precision(.fractionLength(0)))
    }

    /// "3h 20m", or "45m" under an hour
    static func duration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }
}

// MARK: - Summary Card

/// Pushes the stats page from Rail History.
struct RailStatsRoute: Hashable {}

/// The way into the stats from Rail History: the headline figures in one row.
struct RailStatsSummaryCard: View {
    let stats: TravelStats

    private var summary: String {
        var parts = [stats.journeys == 1 ? "1 journey" : "\(stats.journeys) journeys"]
        if stats.journeys > 0 {
            parts.append("\(stats.onTimeText) on time")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.brand)
                .frame(width: 44, height: 44)
                .background(Color.brandTint, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your stats")
                    .font(.headline)
                    .foregroundStyle(Color.ink)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.inkTertiary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .cardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows all your travel stats")
    }
}

// MARK: - Stats Page

/// Everything the Rail History adds up to. Opened from Rail History and from Profile.
struct RailStatsView: View {
    /// Every saved train: a journey of several counts once all of its trains have run
    @Query private var savedTrains: [SavedTrain]

    var body: some View {
        let stats = TravelStats(savedTrains)

        ScrollView {
            if stats.journeys + stats.cancelled == 0 {
                ContentUnavailableView(
                    "No Stats Yet",
                    systemImage: "chart.bar.fill",
                    description: Text("Your journeys are added up here once trains you follow have run.")
                )
                .padding(.top, 60)
            } else {
                VStack(spacing: 14) {
                    headlines(stats)
                    MonthlyJourneysCard(months: stats.months)
                    delays(stats)

                    if !stats.routes.isEmpty {
                        routes(stats)
                    }
                    if !stats.operators.isEmpty {
                        operators(stats)
                    }
                    if stats.claimed + stats.openClaims + stats.missedClaims > 0 {
                        delayRepay(stats)
                    }

                    Text("From your Rail History. Miles are measured in a straight line between stations.")
                        .font(.footnote)
                        .foregroundStyle(Color.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                // Clear of the tab bar, which floats over a page pushed from Rail History
                .padding(.bottom, 96)
            }
        }
        .background(Color.surface)
        .navigationTitle("Your Stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Sections

    private func headlines(_ stats: TravelStats) -> some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatFigureTile(icon: "tram.fill", value: stats.journeys.formatted(), label: "Journeys")
                StatFigureTile(icon: "checkmark.circle.fill", value: stats.onTimeText, label: "On time")
            }
            GridRow {
                StatFigureTile(icon: "clock.fill", value: TravelStats.duration(minutes: stats.delayedMinutes), label: "Delayed in total")
                StatFigureTile(icon: "point.topleft.down.to.point.bottomright.curvepath.fill", value: stats.miles.formatted(), label: "Miles")
            }
        }
    }

    private func delays(_ stats: TravelStats) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Delays and time", systemImage: "hourglass")

                VStack(spacing: 0) {
                    StatRow("Average delay when late", value: stats.averageDelay.map { "\($0) min" } ?? "–")
                    Divider()
                    StatRow("Longest delay", value: stats.longestDelay > 0 ? "\(stats.longestDelay) min" : "–")
                    Divider()
                    StatRow("Cancelled trains", value: stats.cancelled.formatted())
                    Divider()
                    StatRow("Time on trains", value: stats.minutesTravelled > 0 ? TravelStats.duration(minutes: stats.minutesTravelled) : "–")
                }
            }
        }
    }

    private func routes(_ stats: TravelStats) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Most-used routes", systemImage: "arrow.left.arrow.right")

                VStack(spacing: 0) {
                    ForEach(Array(stats.routes.prefix(3).enumerated()), id: \.element.id) { index, route in
                        if index > 0 { Divider() }
                        StatRow(route.name, value: route.journeys.formatted())
                    }
                }
            }
        }
    }

    private func operators(_ stats: TravelStats) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Operators", systemImage: "building.2.fill")

                VStack(spacing: 0) {
                    ForEach(Array(stats.operators.prefix(5).enumerated()), id: \.element.id) { index, company in
                        if index > 0 { Divider() }
                        HStack(spacing: 10) {
                            if OperatorBrand.from(code: company.code) != nil {
                                OperatorLogoBadge(atocCode: company.code, compact: true)
                            } else {
                                Text(company.name)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.ink)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text("\(company.journeys == 1 ? "1 journey" : "\(company.journeys) journeys") · \(company.onTimeText) on time")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.ink)
                                .monospacedDigit()
                        }
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(company.name): \(company.journeys) journeys, \(company.onTimeText) on time")
                    }
                }
            }
        }
    }

    private func delayRepay(_ stats: TravelStats) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Delay Repay", systemImage: "sterlingsign.circle.fill")

                VStack(spacing: 0) {
                    StatRow("Claimed", value: stats.claimed.formatted())
                    Divider()
                    StatRow("Still to claim", value: stats.openClaims.formatted())
                    Divider()
                    StatRow("Window closed unclaimed", value: stats.missedClaims.formatted())
                }

                if stats.openClaims > 0 {
                    NavigationLink {
                        DelayRepayClaimsView()
                    } label: {
                        Text("See what you can claim")
                    }
                    .buttonStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Pieces

/// One headline figure on the stats page.
private struct StatFigureTile: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brand)
                // The symbols differ in height: without this the tiles in a row would too
                .frame(height: 20)
                .accessibilityHidden(true)
            Text(value)
                .font(.title.weight(.bold))
                .foregroundStyle(Color.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value == "–" ? "none" : value)")
    }
}

/// A name and its figure, as the stats cards list them.
private struct StatRow: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.ink)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.ink)
                .monospacedDigit()
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Monthly Chart

/// Journeys in each of the last six months. One series, so the title names it and there is
/// no legend; touching a bar reads out its month.
private struct MonthlyJourneysCard: View {
    let months: [TravelStats.Month]

    @State private var selected: Date?

    private var shown: TravelStats.Month? {
        guard let selected else { return nil }
        return months.first { Calendar.current.isDate($0.start, equalTo: selected, toGranularity: .month) }
    }

    /// Whole journeys only on the axis, however few there are
    private var axisTop: Int {
        max(4, months.map(\.journeys).max() ?? 0)
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel("Journeys by month", systemImage: "calendar")
                    Spacer(minLength: 8)
                    if let shown {
                        Text("\(shown.name): \(shown.journeys)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.ink)
                            .monospacedDigit()
                    }
                }

                Chart(months) { month in
                    BarMark(
                        x: .value("Month", month.start, unit: .month),
                        y: .value("Journeys", month.journeys),
                        width: .ratio(0.55)
                    )
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .continuous))
                    .foregroundStyle(Color.brand)
                    .opacity(shown == nil || shown?.id == month.id ? 1 : 0.35)
                    .accessibilityLabel(month.name)
                    .accessibilityValue(month.journeys == 1 ? "1 journey" : "\(month.journeys) journeys")
                }
                .chartYScale(domain: 0...axisTop)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                            .foregroundStyle(Color.divider)
                        AxisValueLabel()
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
                .chartXSelection(value: $selected)
                .frame(height: 170)
            }
        }
    }
}

#Preview {
    NavigationStack {
        RailStatsView()
    }
    .modelContainer(for: [SavedTrain.self, SavedRoute.self], inMemory: true)
}
