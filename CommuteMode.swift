import SwiftUI
import SwiftData

// MARK: - Commute Mode
// A saved route can be marked as a commute: the days it is travelled, and when the usual
// train leaves. Trainy then follows that train without being asked, from twelve hours before
// it is due. Like everything else the app does unprompted, this happens when it is opened or
// when iOS wakes it for a background refresh.

extension SavedRoute {
    /// Train times are UK local time, wherever the phone is
    static let ukCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .current
        return calendar
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = ukCalendar
        formatter.timeZone = ukCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func day(of date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// The bit for a weekday as Calendar numbers them, Sunday being 1.
    static func bit(forWeekday weekday: Int) -> Int {
        1 << (weekday - 1)
    }

    var isCommute: Bool { commuteDays != 0 }

    func commutes(onWeekday weekday: Int) -> Bool {
        commuteDays & Self.bit(forWeekday: weekday) != 0
    }

    /// When the usual train next leaves: the first commute day at or after `now`.
    func nextCommute(after now: Date = Date()) -> Date? {
        guard isCommute else { return nil }
        let calendar = Self.ukCalendar
        let today = calendar.startOfDay(for: now)

        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  commutes(onWeekday: calendar.component(.weekday, from: day)),
                  let departure = calendar.date(bySettingHour: commuteMinutes / 60, minute: commuteMinutes % 60, second: 0, of: day),
                  departure >= now else { continue }
            return departure
        }
        return nil
    }

    /// "Mon–Fri · 07:42", "Every day · 18:05" or "Mon, Wed · 07:42". Nil when the route is not a commute.
    var commuteSummary: String? {
        guard isCommute else { return nil }
        let time = String(format: "%02d:%02d", commuteMinutes / 60, commuteMinutes % 60)

        // Monday first, as the week is set out in the editor
        let order = [2, 3, 4, 5, 6, 7, 1]
        let chosen = order.filter(commutes(onWeekday:))
        let symbols = Self.ukCalendar.shortWeekdaySymbols

        let days: String
        switch chosen {
        case order: days = "Every day"
        case [2, 3, 4, 5, 6]: days = "Mon–Fri"
        case [7, 1]: days = "Weekends"
        default: days = chosen.map { symbols[$0 - 1] }.joined(separator: ", ")
        }
        return "\(days) · \(time)"
    }
}

@MainActor
final class CommuteMode {

    static let shared = CommuteMode()
    private init() {}

    /// A commute train is followed from this long before it is due to leave
    static let lead: TimeInterval = 12 * 3600

    /// The usual train is the one timetabled nearest the chosen time, within this many minutes
    static let tolerance: TimeInterval = 15 * 60

    /// When each route's train was last searched for. A search that finds nothing is not
    /// repeated on every sync: both feeds limit how often they can be asked.
    private var lastSearch: [PersistentIdentifier: Date] = [:]
    private static let retryInterval: TimeInterval = 20 * 60

    /// Adds the usual train of every commute that is coming up to My Trains.
    func followDueTrains(in context: ModelContext, now: Date = Date()) async {
        let commutes = FetchDescriptor<SavedRoute>(predicate: #Predicate { $0.commuteDays != 0 })

        for route in (try? context.fetch(commutes)) ?? [] {
            guard let departure = route.nextCommute(after: now),
                  departure.timeIntervalSince(now) <= Self.lead else { continue }

            let day = SavedRoute.day(of: departure)
            guard route.lastCommuteDay != day else { continue }

            if let last = lastSearch[route.persistentModelID], now.timeIntervalSince(last) < Self.retryInterval { continue }
            lastSearch[route.persistentModelID] = now

            guard let direct = try? await TrainSearch.departures(
                from: route.originCRS,
                to: route.destinationCRS,
                at: departure.addingTimeInterval(-Self.tolerance)
            ) else { continue }

            let train = Self.nearest(to: departure, among: direct)
            // On a route with no train straight through, the usual journey is one with a change
            let journey = direct.isEmpty ? await usualJourney(on: route, at: departure) : nil

            // The route may have been removed, or its commute changed, during the search
            guard train != nil || journey != nil,
                  route.modelContext != nil, !route.isDeleted,
                  route.nextCommute(after: now) == departure else { continue }

            if let train {
                let saved = (try? context.fetch(FetchDescriptor<SavedTrain>())) ?? []
                if !saved.contains(where: { $0.service?.isSameJourney(as: train) == true }),
                   let data = try? JSONEncoder().encode(train) {
                    context.insert(SavedTrain(id: train.id, serviceData: data))
                    print("🧳 Commute: following the \(train.scheduledDeparture) \(route.originCRS)→\(route.destinationCRS) on \(day)")
                }
            } else if let journey {
                await journey.follow(in: context)
                print("🧳 Commute: following the \(journey.departure.ukClock) \(journey.title), \(journey.summary), on \(day)")
            }
            route.lastCommuteDay = day
            try? context.save()
        }
    }

    /// The journey with a change whose first train is timetabled to leave nearest `departure`,
    /// or nil when the planner cannot be reached or nothing leaves close enough to it.
    private func usualJourney(on route: SavedRoute, at departure: Date) async -> PlannedJourney? {
        guard let origin = route.origin, let destination = route.destination,
              let journeys = try? await JourneyPlanner.shared.journeys(from: origin, to: destination, at: departure.addingTimeInterval(-Self.tolerance)) else { return nil }

        return journeys
            .compactMap { journey in journey.trains.first.map { (journey: journey, gap: abs($0.scheduledDeparture.timeIntervalSince(departure))) } }
            .filter { $0.gap <= Self.tolerance }
            .min { $0.gap < $1.gap }?
            .journey
    }

    /// The train closest to `departure` by the timetable, the earlier one when two are equally close.
    static func nearest(to departure: Date, among trains: [DarwinServiceAdapter]) -> DarwinServiceAdapter? {
        trains
            .compactMap { train in train.scheduledDepartureDate.map { (train: train, gap: abs($0.timeIntervalSince(departure))) } }
            .filter { $0.gap <= tolerance }
            // The search returns trains earliest first, and `min` keeps the first of equals
            .min { $0.gap < $1.gap }?
            .train
    }
}

// MARK: - Commute Editor

/// Sets the days and time of a saved route's commute.
struct CommuteEditorView: View {
    @Bindable var route: SavedRoute

    @Environment(\.modelContext) private var modelContext

    /// Monday first
    private static let weekdays = [2, 3, 4, 5, 6, 7, 1]
    /// Monday to Friday, offered when the commute is first switched on
    private static let workingWeek = [2, 3, 4, 5, 6].reduce(0) { $0 | SavedRoute.bit(forWeekday: $1) }

    /// The days to go back to when the switch is turned on again
    @State private var rememberedDays = CommuteEditorView.workingWeek

    private var isOn: Binding<Bool> {
        Binding(
            get: { route.isCommute },
            set: { on in
                if on {
                    route.commuteDays = rememberedDays == 0 ? Self.workingWeek : rememberedDays
                    if route.commuteMinutes == 0 { route.commuteMinutes = 8 * 60 }
                } else {
                    rememberedDays = route.commuteDays
                    route.commuteDays = 0
                }
                changed()
            }
        )
    }

    /// The commute time as a date on an arbitrary day, for the time picker
    private var time: Binding<Date> {
        let calendar = SavedRoute.ukCalendar
        let midnight = calendar.startOfDay(for: Date())
        return Binding(
            get: { midnight.addingTimeInterval(TimeInterval(route.commuteMinutes * 60)) },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                route.commuteMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                changed()
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Follow My Usual Train", isOn: isOn)
            } header: {
                Text("\(UKStation.name(for: route.originCRS)) to \(UKStation.name(for: route.destinationCRS))")
            } footer: {
                Text("Trainy adds your usual train to My Trains on the days you travel, so you don't have to search for it.")
            }
            .listRowBackground(Color.card)

            if route.isCommute {
                Section {
                    HStack(spacing: 0) {
                        ForEach(Self.weekdays, id: \.self) { weekday in
                            dayButton(weekday)
                        }
                    }
                    .padding(.vertical, 4)

                    DatePicker("Leaves at", selection: time, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, SavedRoute.ukCalendar.timeZone)
                } header: {
                    Text("Days and Time")
                } footer: {
                    Text(footer)
                }
                .listRowBackground(Color.card)
            }
        }
        .appListSurface()
        .tint(Color.brandFill)
        .navigationTitle("Commute")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var footer: String {
        var text = "The train timetabled nearest this time is followed from 12 hours before it leaves, or the nearest journey with a change where no train runs straight through. Trainy can only add it when the app is opened or iOS refreshes it in the background."
        if let next = route.nextCommute() {
            let day = next.formatted(Date.FormatStyle(timeZone: SavedRoute.ukCalendar.timeZone).weekday(.wide))
            text = "Next: \(day) at \(String(format: "%02d:%02d", route.commuteMinutes / 60, route.commuteMinutes % 60)). " + text
        }
        return text
    }

    private func dayButton(_ weekday: Int) -> some View {
        let isChosen = route.commutes(onWeekday: weekday)
        let symbols = SavedRoute.ukCalendar

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            route.commuteDays ^= SavedRoute.bit(forWeekday: weekday)
            changed()
        } label: {
            Text(symbols.veryShortWeekdaySymbols[weekday - 1])
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isChosen ? Color.onBrand : Color.ink)
                .frame(width: 36, height: 36)
                .background(isChosen ? Color.brandFill : Color.subtleFill, in: Circle())
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbols.weekdaySymbols[weekday - 1])
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    /// A changed commute is a new one: follow its train even if today's was already followed.
    private func changed() {
        route.lastCommuteDay = nil
        try? modelContext.save()
    }
}

// MARK: - Commute Settings

/// Every saved route with its commute, if it has one. Opened from Profile.
struct CommuteSettingsView: View {
    @Query(sort: \SavedRoute.addedAt, order: .reverse) private var routes: [SavedRoute]

    var body: some View {
        List {
            if routes.isEmpty {
                ContentUnavailableView(
                    "No Saved Routes",
                    systemImage: "star",
                    description: Text("Save a route first: search for it in Add Train and tap the star. Then set its commute here.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(routes) { route in
                        NavigationLink {
                            CommuteEditorView(route: route)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(UKStation.name(for: route.originCRS)) to \(UKStation.name(for: route.destinationCRS))")
                                    .foregroundStyle(Color.ink)
                                Text(route.commuteSummary ?? "Off")
                                    .font(.footnote)
                                    .foregroundStyle(Color.inkSecondary)
                            }
                        }
                    }
                } header: {
                    Text("Saved Routes")
                } footer: {
                    Text("Choose a route to set the days you travel and your usual train. The way back is a route of its own: save it from Add Train.")
                }
                .listRowBackground(Color.card)
            }
        }
        .appListSurface()
        .navigationTitle("Commute")
        .navigationBarTitleDisplayMode(.inline)
    }
}
