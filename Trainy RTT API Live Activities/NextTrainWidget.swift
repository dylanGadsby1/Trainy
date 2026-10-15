import WidgetKit
import SwiftUI

// MARK: - Next Train Widget
// The next saved train on the Home Screen and Lock Screen: when it leaves, how long until then,
// its platform and whether it is running to time. Shows what the app last wrote at its latest
// sync (TrainyWidgetData), and moves on to the following train once one has left.

typealias WidgetTrain = TrainyWidgetData.Train

struct NextTrainEntry: TimelineEntry {
    let date: Date
    /// Trains still to leave at `date`, soonest first
    let upcoming: [WidgetTrain]
    /// A train that has left and not yet arrived, shown when there is none still to leave
    let onBoard: WidgetTrain?

    var next: WidgetTrain? { upcoming.first }

    init(date: Date, trains: [WidgetTrain]) {
        self.date = date
        // A train stays the next one until a minute after it is due to leave
        upcoming = trains.filter { $0.departs.addingTimeInterval(60) > date }
        onBoard = upcoming.isEmpty
            ? trains.last { !$0.isCancelled && $0.departs <= date && ($0.arrives.map { $0 > date } ?? false) }
            : nil
    }
}

struct NextTrainProvider: TimelineProvider {

    /// How far ahead the minute-by-minute countdown runs before WidgetKit is asked for a new timeline
    private static let countdownMinutes = 90

    func placeholder(in context: Context) -> NextTrainEntry {
        NextTrainEntry(date: Date(), trains: [.sample])
    }

    func getSnapshot(in context: Context, completion: @escaping (NextTrainEntry) -> Void) {
        let trains = TrainyWidgetData.load()
        // The widget gallery shows a sample until a train is saved
        completion(NextTrainEntry(date: Date(), trains: trains.isEmpty && context.isPreview ? [.sample] : trains))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextTrainEntry>) -> Void) {
        let now = Date()
        let trains = TrainyWidgetData.load()
        guard !trains.isEmpty else {
            // The app asks for a reload as soon as a train is saved
            completion(Timeline(entries: [NextTrainEntry(date: now, trains: [])], policy: .after(now.addingTimeInterval(2 * 3600))))
            return
        }

        // Every minute, so "in 12 min" counts down, and whenever a train leaves or arrives
        let minute = Calendar.current.dateInterval(of: .minute, for: now)?.start ?? now
        let horizon = now.addingTimeInterval(TimeInterval(Self.countdownMinutes * 60))
        var dates = Set((0..<Self.countdownMinutes).map { minute.addingTimeInterval(TimeInterval($0 * 60)) })
        for train in trains {
            for date in [train.departs.addingTimeInterval(60), train.arrives].compactMap({ $0 }) where date > now && date < horizon {
                dates.insert(date)
            }
        }

        let entries = dates.sorted().map { NextTrainEntry(date: $0, trains: trains) }
        completion(Timeline(entries: entries, policy: .after(horizon)))
    }
}

// MARK: - Wording

extension WidgetTrain {
    var status: (text: String, color: Color) {
        if isCancelled { return ("Cancelled", WidgetColor.cancelled) }
        if hasUnknownDelay { return ("Delayed", WidgetColor.delayed) }
        if delayMinutes > 0 { return ("\(delayMinutes) min late", WidgetColor.delayed) }
        if isScheduled { return ("Scheduled", WidgetColor.scheduled) }
        return ("On time", WidgetColor.onTime)
    }

    /// "Plat 4", or "Plat TBC" before one is given
    var platformShort: String {
        "Plat \(platform ?? "TBC")"
    }

    /// "Platform 4", saying so when it is only the timetable's plan
    var platformLong: String {
        guard let platform else { return "Platform TBC" }
        return platformConfirmed ? "Platform \(platform)" : "Platform \(platform) · planned"
    }

    /// "in 12 min", "in 1 hr 5 min", "Tomorrow" or "Fri"
    func countdown(from now: Date) -> String {
        let minutes = Int((departs.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "Due now" }
        if minutes < 60 { return "in \(minutes) min" }
        if minutes < 12 * 60 {
            let hours = minutes / 60, rest = minutes % 60
            return rest == 0 ? "in \(hours) hr" : "in \(hours) hr \(rest) min"
        }
        let calendar = Calendar.current
        if calendar.isDateInToday(departs) { return "Later today" }
        if calendar.isDateInTomorrow(departs) { return "Tomorrow" }
        return departs.formatted(.dateTime.weekday(.abbreviated))
    }

    static let sample = WidgetTrain(
        id: "sample",
        originCRS: "HAV", originName: "Havant",
        destinationCRS: "PTR", destinationName: "Petersfield",
        scheduledDeparture: "08:05", expectedDeparture: "08:05",
        departs: Date().addingTimeInterval(12 * 60), arrives: Date().addingTimeInterval(32 * 60),
        expectedArrival: "08:25",
        platform: "2", platformConfirmed: true,
        delayMinutes: 0, isCancelled: false, hasUnknownDelay: false, isScheduled: false,
        operatorName: "South Western", changeAt: nil
    )
}

/// The app's colours (Theme.swift), which the extension does not compile
enum WidgetColor {
    private static func adaptive(_ light: (CGFloat, CGFloat, CGFloat), _ dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(UIColor { traits in
            let (red, green, blue) = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
        })
    }

    static let brand = adaptive((14, 77, 144), (92, 160, 240))
    static let onTime = adaptive((36, 138, 61), (48, 209, 88))
    static let delayed = adaptive((179, 92, 0), (255, 159, 10))
    static let cancelled = adaptive((215, 0, 21), (255, 69, 58))
    static let scheduled = adaptive((94, 107, 126), (154, 166, 184))
}

// MARK: - Views

struct NextTrainWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextTrainEntry

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    // MARK: Home Screen

    private var small: some View {
        Group {
            if let train = entry.next {
                NextTrainSummary(train: train, now: entry.date)
            } else if let train = entry.onBoard {
                OnBoardSummary(train: train)
            } else {
                EmptySummary()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            small

            if let train = entry.next {
                VStack(alignment: .leading, spacing: 6) {
                    if let arrival = train.expectedArrival, !train.isCancelled {
                        DetailRow(systemImage: "flag.checkered", text: "Arrives \(arrival)")
                    }
                    if let change = train.changeAt {
                        DetailRow(systemImage: "arrow.triangle.swap", text: "Change at \(change)")
                    }

                    let later = entry.upcoming.dropFirst().prefix(train.changeAt == nil ? 3 : 2)
                    if !later.isEmpty {
                        Text("Later")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        ForEach(Array(later)) { LaterRow(train: $0) }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    // MARK: Lock Screen

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let train = entry.next {
                Text("\(train.originCRS) → \(train.destinationCRS) · \(train.platformShort)")
                    .font(.headline)
                    .widgetAccentable()
                Text("\(train.expectedDeparture) · \(train.countdown(from: entry.date))")
                    .monospacedDigit()
                Text(train.status.text)
                    .foregroundStyle(.secondary)
            } else if let train = entry.onBoard {
                Text("To \(train.destinationName)")
                    .font(.headline)
                    .widgetAccentable()
                if let arrival = train.expectedArrival {
                    Text("Arrives \(arrival)").monospacedDigit()
                }
            } else {
                Label("No trains", systemImage: "tram.fill")
                    .font(.headline)
                Text("Add one in Trainy")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Group {
            if let train = entry.next {
                if train.isCancelled {
                    Label("\(train.scheduledDeparture) to \(train.destinationName) cancelled", systemImage: "tram.fill")
                } else {
                    Label("\(train.expectedDeparture) to \(train.destinationName) · \(train.platformShort)", systemImage: "tram.fill")
                }
            } else if let train = entry.onBoard, let arrival = train.expectedArrival {
                Label("Arrives \(train.destinationName) \(arrival)", systemImage: "tram.fill")
            } else {
                Label("No trains", systemImage: "tram.fill")
            }
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "tram.fill")
                    .font(.caption2)
                    .widgetAccentable()
                if let train = entry.next {
                    Text(train.isCancelled ? "Canc" : train.expectedDeparture)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                    if let platform = train.platform, !train.isCancelled {
                        Text("P\(platform)")
                            .font(.system(size: 10, weight: .medium))
                    }
                } else {
                    Text("–")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .padding(4)
        }
    }
}

// MARK: - Pieces

/// The next train: route, time, countdown, status and platform
private struct NextTrainSummary: View {
    let train: WidgetTrain
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(train.operatorName ?? "Next train")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "tram.fill")
                    .font(.caption2)
                    .foregroundStyle(WidgetColor.brand)
            }

            Spacer(minLength: 4)

            Text("\(train.originCRS) → \(train.destinationCRS)")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(train.isCancelled ? train.scheduledDeparture : train.expectedDeparture)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .strikethrough(train.isCancelled)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if train.delayMinutes > 0, !train.isCancelled, train.expectedDeparture != train.scheduledDeparture {
                    Text(train.scheduledDeparture)
                        .font(.caption)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                }
            }

            if !train.isCancelled {
                Text(train.countdown(from: now))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetColor.brand)
            }

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Circle()
                    .fill(train.status.color)
                    .frame(width: 6, height: 6)
                Text(train.status.text)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(train.status.color)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(train.platformShort)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(train.platformConfirmed ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// A train that has left, with nothing else still to come
private struct OnBoardSummary: View {
    let train: WidgetTrain

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: "tram.fill")
                .font(.caption)
                .foregroundStyle(WidgetColor.brand)
            Spacer(minLength: 4)
            Text("On the way to")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(train.destinationName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            if let arrival = train.expectedArrival {
                Text("Arrives \(arrival)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(WidgetColor.brand)
            }
        }
    }
}

private struct EmptySummary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "tram.fill")
                .font(.title3)
                .foregroundStyle(WidgetColor.brand)
            Spacer(minLength: 4)
            Text("No trains")
                .font(.subheadline.weight(.semibold))
            Text("Add one in Trainy to see it here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DetailRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label {
            Text(text).lineLimit(1)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(.secondary)
        }
        .font(.caption.weight(.medium))
        .monospacedDigit()
    }
}

private struct LaterRow: View {
    let train: WidgetTrain

    var body: some View {
        HStack(spacing: 6) {
            Text(train.isCancelled ? train.scheduledDeparture : train.expectedDeparture)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .strikethrough(train.isCancelled)
            Text(train.destinationCRS)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Circle()
                .fill(train.status.color)
                .frame(width: 6, height: 6)
        }
    }
}

// MARK: - Widget

struct NextTrainWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TrainyWidgetData.kind, provider: NextTrainProvider()) { entry in
            NextTrainWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(UIColor.systemBackground) }
        }
        .configurationDisplayName("Next Train")
        .description("Your next saved train: when it leaves, its platform and whether it is on time.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

#Preview(as: .systemMedium) {
    NextTrainWidget()
} timeline: {
    NextTrainEntry(date: .now, trains: [.sample])
}
