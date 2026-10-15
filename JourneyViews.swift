import SwiftUI
import SwiftData

// MARK: - Connections

/// The change from one train of a journey to the next, as things stand now.
struct JourneyConnection {
    /// No change is planned or counted as safe with less than this between trains. The
    /// timetable data the planner uses has no official connection times.
    static let minimumMinutes = 5

    enum State {
        case comfortable
        /// Less time than the change needs
        case tight
        /// The next train leaves before the first arrives
        case missed
        /// One of the two trains is cancelled
        case broken
    }

    let arriving: DarwinServiceAdapter
    let departing: DarwinServiceAdapter
    /// How the traveller gets between the two, when that is more than a change of platform
    let note: String?
    /// Minutes the change needs
    let needed: Int
    /// The platform the first train arrives at: live from the arrival board once it is nearly
    /// due, and until then the timetable's
    let arrivalPlatform: String?
    /// The Tube lines the change uses, by Transport for London's names
    let tubeLines: [String]

    init?(from first: SavedTrain, to second: SavedTrain) {
        guard let arriving = first.service, let departing = second.service else { return nil }
        self.arriving = arriving
        self.departing = departing
        self.note = second.transferNote
        self.needed = max(second.transferMinutes ?? Self.minimumMinutes, Self.minimumMinutes)
        self.arrivalPlatform = arriving.arrivalPlatform ?? first.arrivalPlatform
        self.tubeLines = second.transferLines?.split(separator: ",").map(String.init) ?? Self.line(in: second.transferNote)
    }

    /// The line named in a note such as "Victoria line from Euston to Victoria", for a
    /// journey saved before its lines were recorded.
    private static func line(in note: String?) -> [String] {
        guard let note, let range = note.range(of: " line from ") else { return [] }
        return [String(note[..<range.lowerBound])]
    }

    /// True until the next train has gone: while the change is still to be made
    var isUpcoming: Bool {
        (departing.expectedDepartureDate ?? .distantPast) > Date()
    }

    /// "Due into platform 4 · leaves from platform 11". Each platform is live once Darwin
    /// has it, and the timetable's until then.
    var platformsText: String? {
        let arrival = arrivalPlatform.map { "due into platform \($0)" }
        let departure = departing.platform.isEmpty || departing.platform == "TBC" ? nil : "leaves from platform \(departing.platform)"
        let text = [arrival, departure].compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? nil : text.prefix(1).uppercased() + text.dropFirst()
    }

    var station: String {
        UKStation.name(for: departing.userSearchOriginCRS ?? departing.originCRS)
    }

    /// Minutes between the first train's expected arrival and the next one's expected departure
    var minutes: Int? {
        guard let arrival = arriving.expectedArrivalDate, let departure = departing.expectedDepartureDate else { return nil }
        return Int(departure.timeIntervalSince(arrival) / 60)
    }

    var state: State {
        if arriving.isCancelledService || departing.isCancelledService { return .broken }
        // Late with no new time: nobody can say the change is safe
        if arriving.hasUnknownDelay == true { return .tight }
        guard let minutes else { return .comfortable }
        if minutes < 1 { return .missed }
        return minutes < needed ? .tight : .comfortable
    }

    /// True while the change is still to come: the first train has not arrived and the next has not gone.
    func isAhead(at now: Date = Date()) -> Bool {
        arriving.hasArrived != true && (departing.expectedDepartureDate ?? .distantPast) > now
    }

    /// "Change at Birmingham New Street", or the walk or ride between two stations
    var title: String {
        note ?? "Change at \(station)"
    }

    var detail: String {
        switch state {
        case .broken:
            let cancelled = arriving.isCancelledService ? arriving : departing
            return "The \(cancelled.scheduledDeparture) is cancelled"
        case .missed:
            return "The \(departing.realtimeDeparture) leaves before you arrive"
        case .tight:
            guard arriving.hasUnknownDelay != true, let minutes else { return "Your train is delayed, with no new time yet" }
            return "Only \(minutes) min between trains"
        case .comfortable:
            return minutes.map { "\($0) min between trains" } ?? "Times to be confirmed"
        }
    }

    /// A few words for a train card, when the change needs the traveller's attention.
    var warning: String? {
        switch state {
        case .comfortable: return nil
        case .tight: return "Tight change"
        case .missed: return "Change at risk"
        case .broken: return "Journey disrupted"
        }
    }

    var color: Color {
        switch state {
        case .comfortable: return .inkSecondary
        case .tight: return .statusDelayed
        case .missed, .broken: return .statusCancelled
        }
    }

    var systemImage: String {
        switch state {
        case .comfortable: return "arrow.triangle.swap"
        case .tight: return "exclamationmark.triangle.fill"
        case .missed, .broken: return "xmark.octagon.fill"
        }
    }
}

// MARK: - Adding the Next Train

/// Where and when a journey can carry on from a saved train: its arrival station, from the
/// earliest a change there can be made.
struct NextTrainStart {
    let station: UKStation
    let earliest: Date
}

extension SavedTrain {
    /// Nil once the train has run, or when where it arrives is not known.
    var nextTrainStart: NextTrainStart? {
        guard !isPast, let service, !service.isCancelledService,
              let station = ukStations.first(where: { $0.crs == (service.userSearchDestinationCRS ?? service.destinationCRS) }),
              let arrival = service.expectedArrivalDate ?? service.scheduledArrivalDate else { return nil }
        return NextTrainStart(station: station, earliest: arrival.addingTimeInterval(TimeInterval(JourneyConnection.minimumMinutes * 60)))
    }

    /// Follows `train` as the next train of this one's journey: the way to build a journey
    /// the planner does not offer, one train at a time. This train becomes the start of a
    /// journey if it was followed on its own. A train already in My Trains joins rather
    /// than appearing twice.
    @MainActor
    func addNext(_ train: DarwinServiceAdapter, in context: ModelContext) {
        guard let previous = service else { return }
        let all = (try? context.fetch(FetchDescriptor<SavedTrain>())) ?? []

        let journeyID = self.journeyID ?? UUID().uuidString
        if self.journeyID == nil {
            self.journeyID = journeyID
            legIndex = 0
        }

        let record: SavedTrain
        if let existing = all.first(where: { !$0.isPast && !$0.isDeleted && $0.service?.isSameJourney(as: train) == true }) {
            record = existing
        } else if let data = try? JSONEncoder().encode(train) {
            record = SavedTrain(id: train.id, serviceData: data)
            context.insert(record)
        } else {
            return
        }
        record.journeyID = journeyID
        record.legIndex = legIndex + 1

        // A change at the same station needs only the usual minimum. Between two stations,
        // allow a walk: about twelve minutes a kilometre, and five more to find the platform.
        let arrivalCRS = previous.userSearchDestinationCRS ?? previous.destinationCRS
        let departureCRS = train.userSearchOriginCRS ?? train.originCRS
        if arrivalCRS == departureCRS {
            record.transferNote = nil
            record.transferMinutes = nil
        } else {
            record.transferNote = "Make your own way from \(UKStation.name(for: arrivalCRS)) to \(UKStation.name(for: departureCRS))"
            if let from = knownStationCoordinates[arrivalCRS], let to = knownStationCoordinates[departureCRS] {
                record.transferMinutes = Int(RouteLine.metres(from: from, to: to) / 1000 * 12) + 5
            }
        }
        record.transferLines = nil
        record.arrivalPlatform = nil

        // The journey as a whole: named from its first station to its new last one, and
        // planned to end when this train is due, which Delay Repay measures against
        var legs = all.filter { $0.journeyID == journeyID && !$0.isDeleted }
        if !legs.contains(where: { $0 === record }) { legs.append(record) }
        legs.sort { $0.legIndex < $1.legIndex }

        let firstCRS = legs.first?.service.map { $0.userSearchOriginCRS ?? $0.originCRS } ?? (previous.userSearchOriginCRS ?? previous.originCRS)
        let lastCRS = train.userSearchDestinationCRS ?? train.destinationCRS
        let title = "\(UKStation.name(for: firstCRS)) to \(UKStation.name(for: lastCRS))"
        for leg in legs {
            leg.journeyTitle = title
            leg.journeyPlannedArrival = train.scheduledArrivalDate
            leg.onwardNote = nil
        }

        try? context.save()
    }
}

// MARK: - Saved Journeys

/// The trains of one journey, in the order they are taken.
struct SavedJourney {
    let id: String
    let legs: [SavedTrain]

    init(id: String, legs: [SavedTrain]) {
        self.id = id
        self.legs = legs
    }

    /// Nil when `train` was saved on its own.
    init?(containing train: SavedTrain, in trains: [SavedTrain]) {
        guard let id = train.journeyID else { return nil }
        self.id = id
        self.legs = trains
            .filter { $0.journeyID == id && $0.service != nil }
            .sorted { $0.legIndex < $1.legIndex }
    }

    var title: String {
        legs.first?.journeyTitle ?? "Your journey"
    }

    var services: [DarwinServiceAdapter] {
        legs.compactMap(\.service)
    }

    /// One train with nothing either side of it needs no journey: it is just a train.
    var isWorthShowing: Bool {
        legs.count > 1 || legs.contains { $0.transferNote != nil || $0.onwardNote != nil }
    }

    func position(of train: SavedTrain) -> Int? {
        legs.firstIndex { $0.persistentModelID == train.persistentModelID }
    }

    /// The change onto the leg at `index` from the one before it.
    func connection(before index: Int) -> JourneyConnection? {
        guard index > 0, legs.indices.contains(index) else { return nil }
        return JourneyConnection(from: legs[index - 1], to: legs[index])
    }

    /// "1 change", "2 changes"
    var changesText: String {
        legs.count == 2 ? "1 change" : "\(max(0, legs.count - 1)) changes"
    }

    /// The first change still to come that a delay has put in doubt.
    func connectionAtRisk(at now: Date = Date()) -> JourneyConnection? {
        legs.indices
            .compactMap { connection(before: $0) }
            .first { $0.isAhead(at: now) && $0.warning != nil }
    }

    /// How the journey stands as a whole. A train already left behind no longer counts:
    /// what matters is the trains still to come and when the last one gets in.
    var status: (label: String, color: Color) {
        let services = services
        if services.contains(where: \.isCancelledService) {
            return ("Disrupted", .statusCancelled)
        }

        let remaining = legs.filter { !$0.isPast && $0.service?.hasArrived != true }.compactMap(\.service)
        let counted = remaining.isEmpty ? Array(services.suffix(1)) : remaining

        let status: TrainStatus
        // Late too when its trains are on time but it was re-planned to end later than first meant
        if counted.contains(where: { $0.delayMinutes > 0 || $0.hasUnknownDelay == true }) || connectionAtRisk() != nil
            || (disruptedBy != nil && minutesLate > 0) {
            status = .delayed
        } else if counted.allSatisfy({ $0.isAwaitingLiveData == true }) {
            status = .scheduled
        } else {
            status = .onTime
        }
        return (status.label, status.color)
    }

    /// Fraction of the whole journey done at `now`, changes included: 0 before the first
    /// train leaves, 1 once the last is due in.
    func progress(at now: Date = Date()) -> Double {
        let services = services
        guard let start = services.first?.expectedDepartureDate,
              let end = services.last?.expectedArrivalDate, end > start else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }

    /// The train the traveller is on, or is waiting for: the first that has yet to get in.
    func currentLeg(at now: Date = Date()) -> DarwinServiceAdapter? {
        let upcoming = legs.filter { !$0.isPast }.compactMap(\.service)
        return upcoming.first { $0.hasArrived != true && ($0.expectedArrivalDate ?? .distantFuture) > now } ?? upcoming.last
    }

    /// When the journey was due to end as it was first planned.
    var plannedArrival: Date? {
        legs.compactMap(\.journeyPlannedArrival).first ?? services.last?.scheduledArrivalDate
    }

    /// The operator whose train first broke the journey as planned, when it had to be re-planned
    var disruptedBy: String? {
        legs.compactMap(\.journeyDisruptedBy).first
    }

    /// How late the journey ends, or ended, against when it was first planned to: the last
    /// train's own lateness, and any later trains a missed change has meant taking.
    var minutesLate: Int {
        guard let last = services.last else { return 0 }
        if let planned = plannedArrival, let arrival = last.expectedArrivalDate {
            return max(0, Int(arrival.timeIntervalSince(planned) / 60))
        }
        return last.delayMinutes
    }

    /// Where the journey ends, as a station
    var destinationStation: UKStation? {
        guard let last = services.last else { return nil }
        let crs = last.userSearchDestinationCRS ?? last.destinationCRS
        return ukStations.first { $0.crs == crs }
    }

    /// Where and when to plan from to get round the change onto the train at `index`, and
    /// the position of the first train a new plan would replace.
    func replanStart(before index: Int) -> (station: UKStation, time: Date, from: Int)? {
        guard let connection = connection(before: index) else { return nil }
        let arriving = connection.arriving

        // The train to the change is not running: start again from where it would have left
        let crs = arriving.isCancelledService
            ? arriving.userSearchOriginCRS ?? arriving.originCRS
            : arriving.userSearchDestinationCRS ?? arriving.destinationCRS
        let time = arriving.isCancelledService ? arriving.scheduledDepartureDate : arriving.expectedArrivalDate

        guard let station = ukStations.first(where: { $0.crs == crs }), let time else { return nil }
        return (station, time, arriving.isCancelledService ? index - 1 : index)
    }

    /// The Delay Repay claim for the journey as a whole, with the train it is recorded
    /// against. Compensation goes by how late the traveller reached the end of the journey,
    /// a missed connection included, and is claimed from the operator whose train went wrong first.
    var delayRepay: (train: SavedTrain, claim: DelayRepayClaim)? {
        // One train is claimed for as a train, unless it is what is left of a journey that was re-planned
        guard legs.count > 1 || disruptedBy != nil, legs.allSatisfy(\.isPast),
              let record = legs.first, let first = record.service else { return nil }

        let services = services
        let cause = disruptedBy ?? services.first { $0.isCancelledService || $0.delayMinutes > 0 }?.atocCode
        guard let brand = OperatorBrand.from(code: cause),
              let url = brand.delayRepayURL.flatMap({ URL(string: $0) }) else { return nil }

        let isCancelled = services.contains(where: \.isCancelledService)
        let late = minutesLate
        guard isCancelled || late >= brand.delayRepayThreshold else { return nil }

        let travelled = first.scheduledDepartureDate ?? record.addedAt
        let deadline = Calendar.current.date(byAdding: .day, value: DelayRepayClaim.claimWindowDays, to: travelled) ?? travelled

        return (record, DelayRepayClaim(
            brand: brand,
            url: url,
            delayMinutes: late,
            isCancelled: isCancelled,
            deadline: deadline,
            claimedAt: record.delayRepayClaimedAt,
            isJourney: true
        ))
    }

    /// The journey as it stands, in a sentence or two for someone who is waiting for the traveller.
    func shareMessage(at now: Date = Date()) -> String {
        let services = services
        guard let first = services.first, let last = services.last else { return title }

        func name(_ crs: String) -> String { UKStation.name(for: crs) }
        let origin = name(first.userSearchOriginCRS ?? first.originCRS)
        let destination = name(last.userSearchDestinationCRS ?? last.destinationCRS)

        if let cancelled = services.first(where: \.isCancelledService) {
            let from = name(cancelled.userSearchOriginCRS ?? cancelled.originCRS)
            return "My journey from \(origin) to \(destination) has been disrupted: the \(cancelled.scheduledDeparture) from \(from) is cancelled."
        }

        let hasLeft = (first.expectedDepartureDate ?? .distantFuture) <= now
        let day = first.dayLabel(at: now).map { $0 == "Tomorrow" ? " tomorrow" : " on \($0)" } ?? ""
        let opening = hasLeft
            ? "I'm on my way from \(origin) to \(destination)"
            : "I'm travelling from \(origin) to \(destination)\(day), leaving at \(first.realtimeDeparture)"

        let changes = ListFormatter.localizedString(byJoining: services.dropLast().map { name($0.userSearchDestinationCRS ?? $0.destinationCRS) })
        let arrival = last.userSearchDestinationArrivalTime ?? last.userSearchDestinationScheduledArrivalTime ?? "--:--"

        let lateness = minutesLate > 0 ? ", about \(TravelStats.duration(minutes: minutesLate)) later than planned" : ""

        var message = "\(opening), changing at \(changes). Due in at \(arrival)\(lateness)."
        if let train = currentLeg(at: now), let link = train.liveTrackingURL {
            message += "\n\(hasLeft ? "Follow the train I'm on" : "Follow my first train"): \(link.absoluteString)"
        }
        return message
    }

    /// The train to be on a platform for next: the first still to leave, or the last one once it has.
    func boardingLeg(at now: Date = Date()) -> DarwinServiceAdapter? {
        let upcoming = legs.filter { !$0.isPast }.compactMap(\.service)
        return upcoming.first { ($0.expectedDepartureDate ?? .distantFuture) > now } ?? upcoming.last ?? services.last
    }
}

// MARK: - Travel Items

/// Names a journey of several trains: the page Rail History pushes for it, and the sheet
/// My Trains shows.
struct JourneyRoute: Hashable, Identifiable {
    let id: String
}

/// What My Trains and Rail History list: a train followed on its own, or a journey of
/// several trains as one.
enum TravelItem: Identifiable {
    case train(SavedTrain)
    case journey(SavedJourney)

    enum ID: Hashable {
        case train(PersistentIdentifier)
        case journey(String)
    }

    var id: ID {
        switch self {
        case .train(let train): return .train(train.persistentModelID)
        case .journey(let journey): return .journey(journey.id)
        }
    }

    var legs: [SavedTrain] {
        switch self {
        case .train(let train): return [train]
        case .journey(let journey): return journey.legs
        }
    }

    /// When the first train is due to leave
    var departure: Date {
        legs.first.flatMap { $0.service?.scheduledDepartureDate ?? $0.addedAt } ?? .distantFuture
    }

    /// When the last train finished, for one that has
    var finishedAt: Date {
        legs.map { $0.movedToPastAt ?? $0.addedAt }.max() ?? .distantPast
    }

    /// The journey this item is, when it is one: several trains, or the one train left of
    /// a journey that had to be re-planned.
    private var journey: SavedJourney? {
        switch self {
        case .journey(let journey):
            return journey
        case .train(let train):
            guard train.journeyDisruptedBy != nil, let id = train.journeyID else { return nil }
            return SavedJourney(id: id, legs: [train])
        }
    }

    /// The Delay Repay claims on the item, each with the train it is recorded against. A
    /// journey has one at most, for the journey as a whole.
    var claims: [(train: SavedTrain, claim: DelayRepayClaim)] {
        if let journey { return journey.delayRepay.map { [$0] } ?? [] }
        return legs.first.flatMap { train in train.delayRepay.map { [(train, $0)] } } ?? []
    }

    /// Minutes late at the end, against the journey as first planned
    var minutesLate: Int {
        journey?.minutesLate ?? legs.first?.service?.delayMinutes ?? 0
    }
}

extension Array where Element == SavedTrain {
    /// The trains as My Trains and Rail History list them, a journey of several trains
    /// being one item. Call it on every saved train, so that a journey is whole.
    /// - Parameter past: True for Rail History: single trains that have run, and journeys
    ///   whose every train has. False for My Trains, which keeps a journey until its last
    ///   train is done, soonest first.
    func travelItems(past: Bool) -> [TravelItem] {
        var journeys: [String: [SavedTrain]] = [:]
        for train in self where train.service != nil {
            if let id = train.journeyID {
                journeys[id, default: []].append(train)
            }
        }

        var items: [TravelItem] = []
        var listed: Set<String> = []
        for train in self where train.service != nil {
            // A journey down to one train is listed as that train
            guard let id = train.journeyID, let legs = journeys[id], legs.count > 1 else {
                if train.isPast == past { items.append(.train(train)) }
                continue
            }
            guard listed.insert(id).inserted, legs.allSatisfy(\.isPast) == past else { continue }
            items.append(.journey(SavedJourney(id: id, legs: legs.sorted { $0.legIndex < $1.legIndex })))
        }

        return past
            ? items.sorted { $0.finishedAt > $1.finishedAt }
            : items.sorted { $0.departure < $1.departure }
    }

    /// Every change still to come, keyed by journey and leg, for telling what a refresh altered.
    var connectionStates: [String: JourneyConnection.State] {
        var states: [String: JourneyConnection.State] = [:]
        for (key, connection) in connections {
            states[key] = connection.state
        }
        return states
    }

    var connections: [String: JourneyConnection] {
        var found: [String: JourneyConnection] = [:]
        for train in self where !train.isPast && train.journeyID != nil {
            guard let journey = SavedJourney(containing: train, in: self),
                  let index = journey.position(of: train),
                  let connection = journey.connection(before: index) else { continue }
            found["\(journey.id).\(index)"] = connection
        }
        return found
    }
}

// MARK: - Routes With a Change (search results)

/// Under the direct trains in the search results: routes that need a change, from the journey planner.
struct JourneyOptionsSection: View {
    let query: TrainSearchQuery
    /// Look straight away, without waiting to be asked: there are no direct trains to show
    let loadsAtOnce: Bool
    /// Called once a journey has been added to My Trains
    var onAdded: () -> Void

    private enum Phase {
        case idle
        case loading
        case loaded([PlannedJourney])
        case failed(String)
    }

    @State private var phase = Phase.idle
    @State private var selected: PlannedJourney?

    // How routes are planned. Kept between searches, and used for a commute and a missed change too.
    @AppStorage(JourneyOptions.extraChangeMinutesKey) private var extraChangeMinutes = 0
    @AppStorage(JourneyOptions.fewestChangesKey) private var fewestChanges = false
    @AppStorage(JourneyOptions.avoidTubeKey) private var avoidTube = false

    private var optionsAreSet: Bool {
        extraChangeMinutes > 0 || fewestChanges || avoidTube
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Routes with a change", systemImage: "arrow.triangle.swap")
                Spacer(minLength: 8)
                Menu {
                    Picker("Time for Each Change", selection: $extraChangeMinutes) {
                        Text("Standard").tag(0)
                        Text("5 Minutes Longer").tag(5)
                        Text("10 Minutes Longer").tag(10)
                        Text("15 Minutes Longer").tag(15)
                    }
                    .pickerStyle(.menu)
                    Toggle("Fewest Changes", isOn: $fewestChanges)
                    Toggle("Avoid the Tube", isOn: $avoidTube)
                } label: {
                    Label("Options", systemImage: "slider.horizontal.3")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(optionsAreSet ? Color.brand : Color.inkSecondary)
                        .frame(minHeight: 44)
                }
            }
            .padding(.leading, 4)
            .padding(.top, 8)

            switch phase {
            case .idle:
                Button("Find Routes with a Change") {
                    Task { await load() }
                }
                .buttonStyle(.secondary)

            case .loading:
                ProgressView("Planning routes…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)

            case .failed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try Again") {
                        Task { await load() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                }
                .padding(.horizontal, 4)

            case .loaded(let journeys) where journeys.isEmpty:
                Text("No routes with a change were found around this time.")
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.horizontal, 4)

            case .loaded(let journeys):
                ForEach(journeys) { journey in
                    Button {
                        selected = journey
                    } label: {
                        PlannedJourneyRow(journey: journey)
                    }
                    .buttonStyle(.plain)
                }
                TransitousCredit()
            }
        }
        .navigationDestination(item: $selected) { journey in
            PlannedJourneyDetailView(journey: journey, onAdded: onAdded)
        }
        .task {
            if loadsAtOnce, case .idle = phase {
                await load()
            }
        }
        // A changed option is a new search, once there has been one to change
        .onChange(of: JourneyOptions(extraChangeMinutes: extraChangeMinutes, fewestChanges: fewestChanges, avoidTube: avoidTube)) {
            if case .idle = phase { return }
            Task { await load() }
        }
    }

    private func load() async {
        phase = .loading
        do {
            phase = .loaded(try await JourneyPlanner.shared.journeys(from: query.origin, to: query.destination, at: query.date))
        } catch {
            // The screen was left mid-search: ask again on return
            if Task.isCancelled {
                phase = .idle
                return
            }
            phase = .failed(JourneyPlanner.message(for: error))
        }
    }
}

/// The link Transitous asks for wherever its routes are shown.
struct TransitousCredit: View {
    var body: some View {
        Link(destination: JourneyPlanner.sourcesURL) {
            Text("Routes planned by Transitous. See its data sources.")
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
                .underline()
                .multilineTextAlignment(.leading)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 4)
    }
}

/// One route in the search results.
struct PlannedJourneyRow: View {
    let journey: PlannedJourney

    /// Each operator once, in the order their trains are taken
    private var operators: [OperatorSummary.Operator] {
        OperatorSummary.Operator.distinct(journey.trains.map { .init(code: $0.operatorCode, name: $0.operatorName) })
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(journey.departure.ukClock)
                    Image(systemName: "arrow.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.inkTertiary)
                    Text(journey.arrival.ukClock)
                    Spacer(minLength: 8)
                    Text(journey.durationText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.inkSecondary)
                }
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.ink)
                .monospacedDigit()

                OperatorSummary(operators: operators, compact: true)

                Text(journey.summary)
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.inkTertiary)
        }
        .padding(16)
        .cardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Leaves \(journey.departure.ukClock), arrives \(journey.arrival.ukClock), takes \(journey.durationText), \(journey.summary)")
        .accessibilityHint("Shows the route")
    }
}

// MARK: - A Planned Journey

/// One route laid out train by train, with the button that follows it.
struct PlannedJourneyDetailView: View {
    let journey: PlannedJourney
    /// Called once the journey has been added to My Trains
    var onAdded: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<SavedTrain> { $0.isPast == false }) private var savedTrains: [SavedTrain]

    @State private var isAdding = false

    /// Every train of the journey is already being followed
    private var isFollowed: Bool {
        journey.trains.allSatisfy { leg in
            let train = DarwinServiceAdapter(planned: leg)
            return savedTrains.contains { $0.journeyID != nil && $0.service?.isSameJourney(as: train) == true }
        }
    }

    private var heading: String {
        let day = Calendar.current.isDateInToday(journey.departure)
            ? "Today"
            : journey.departure.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return "\(day) · \(journey.durationText)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SheetHeader(journey.title, eyebrow: heading)

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(journey.parts.enumerated()), id: \.offset) { _, part in
                            switch part {
                            case .train(let leg):
                                trainRow(leg)
                            case .transfer(let transfer):
                                transferRow(transfer)
                            }
                        }
                    }
                }

                Text("Trainy follows each train and warns you when a delay puts a change at risk. Times are the timetable's until each train goes live.")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.horizontal, 4)

                TransitousCredit()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.surface)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await add() }
            } label: {
                if isAdding {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(Color.onBrand)
                        Text("Finding Your Trains…")
                    }
                } else {
                    Label(isFollowed ? "In My Trains" : "Add Journey to My Trains", systemImage: isFollowed ? "checkmark" : "plus")
                }
            }
            .buttonStyle(.primary)
            .disabled(isFollowed || isAdding)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.surface)
        }
    }

    private func trainRow(_ leg: PlannedLeg) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(leg.scheduledDeparture.ukClock)
                    .font(.headline)
                    .foregroundStyle(Color.ink)
                Text(leg.scheduledArrival.ukClock)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.inkSecondary)
            }
            .monospacedDigit()
            .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(leg.originName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ink)
                Text("to \(leg.destinationName)")
                    .font(.subheadline)
                    .foregroundStyle(Color.ink)

                HStack(spacing: 6) {
                    if OperatorBrand.from(code: leg.operatorCode) != nil {
                        OperatorLogoBadge(atocCode: leg.operatorCode, compact: true)
                    } else {
                        Text(leg.operatorName ?? "Train")
                    }
                    if let platform = leg.platform {
                        Text("·")
                        Text("Platform \(platform)")
                    }
                }
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(1)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(leg.scheduledDeparture.ukClock) from \(leg.originName), arriving \(leg.destinationName) at \(leg.scheduledArrival.ukClock)")
    }

    private func transferRow(_ transfer: PlannedTransfer) -> some View {
        HStack(spacing: 12) {
            Image(systemName: transfer.systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.brand)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(transfer.text)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if transfer.minutes > 0 {
                    Text("About \(transfer.minutes) min")
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func add() async {
        isAdding = true
        await journey.follow(in: modelContext)
        isAdding = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onAdded()
    }
}

// MARK: - Journey Rows

/// The change between two trains of a journey, and whether there is still time for it.
struct ConnectionRow: View {
    let connection: JourneyConnection

    /// How the Tube lines the change uses are running
    @State private var tube: [TubeStatus.Line] = []

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: connection.systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(connection.state == .comfortable ? Color.brand : connection.color)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(connection.detail)
                    .font(.caption.weight(connection.state == .comfortable ? .regular : .semibold))
                    .foregroundStyle(connection.color)

                // Where to go, while the change is still to be made
                if connection.isUpcoming, let platforms = connection.platformsText {
                    Text(platforms)
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(tube, id: \.name) { line in
                    Text("\(line.name) line: \(line.status.prefix(1) + line.status.dropFirst().lowercased())")
                        .font(.caption.weight(line.isGood ? .regular : .semibold))
                        .foregroundStyle(line.isGood ? Color.inkSecondary : Color.statusDelayed)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .task(id: connection.tubeLines) {
            // Only for a change coming up soon: how a line is running now says little about tomorrow
            guard connection.isUpcoming, let arrival = connection.arriving.expectedArrivalDate,
                  arrival.timeIntervalSinceNow < 3 * 3600 else {
                tube = []
                return
            }
            tube = await TubeStatus.shared.lines(named: connection.tubeLines)
        }
    }
}

/// Under a change that is in doubt: the later ways to finish the journey, each with a button
/// that takes it up in place of the trains that can no longer be caught.
private struct OnwardOptionsCard: View {
    let journey: SavedJourney
    /// The position of the train the change is onto
    let index: Int

    @Environment(\.modelContext) private var modelContext

    private enum Phase {
        case loading
        case loaded([PlannedJourney])
        case failed(String)
    }

    @State private var phase = Phase.loading
    /// The option being switched to, while its trains are looked up
    @State private var switchingTo: String?

    /// Looked up again when the place to plan from changes, or the time moves by more than
    /// a few minutes: a late train's estimate shifts minute by minute, and the planner is
    /// a shared, free service
    private var loadKey: String {
        let start = journey.replanStart(before: index)
        return "\(journey.id).\(index).\(start?.station.crs ?? "").\(Int((start?.time.timeIntervalSince1970 ?? 0) / 300))"
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Later ways to get there", systemImage: "arrow.triangle.branch")

                switch phase {
                case .loading:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Looking for later trains…")
                            .font(.subheadline)
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .frame(minHeight: 44)

                case .failed(let message):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Try Again") {
                            Task { await load() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                    }

                case .loaded(let options) where options.isEmpty:
                    Text("No later trains were found from here in the next hour or so.")
                        .font(.subheadline)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                case .loaded(let options):
                    VStack(spacing: 0) {
                        ForEach(Array(options.enumerated()), id: \.element.id) { position, option in
                            if position > 0 { Divider() }
                            row(option)
                        }
                    }
                    TransitousCredit()
                }
            }
        }
        .task(id: loadKey) {
            await load()
        }
    }

    private func row(_ option: PlannedJourney) -> some View {
        var facts: [String] = []
        if let planned = journey.plannedArrival {
            let minutes = Int(option.arrival.timeIntervalSince(planned) / 60)
            if minutes > 0 { facts.append("\(TravelStats.duration(minutes: minutes)) later than planned") }
        }
        // Said when the next train goes from somewhere else: across London, say
        if let first = option.trains.first, let start = journey.replanStart(before: index), first.originCRS != start.station.crs {
            facts.append("from \(first.originName)")
        }
        if option.changes > 0 {
            facts.append(option.changes == 1 ? "1 change" : "\(option.changes) changes")
        }
        if let platform = option.trains.first?.platform { facts.append("platform \(platform)") }
        if let first = facts.first { facts[0] = first.prefix(1).uppercased() + first.dropFirst() }

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text((option.trains.first?.scheduledDeparture ?? option.departure).ukClock)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.inkTertiary)
                    Text(option.arrival.ukClock)
                }
                .font(.headline)
                .foregroundStyle(Color.ink)
                .monospacedDigit()

                Text(facts.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            Button {
                Task { await take(option) }
            } label: {
                Group {
                    if switchingTo == option.id {
                        ProgressView()
                            .tint(Color.onBrand)
                    } else {
                        Text("Switch")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.onBrand)
                .frame(minWidth: 44)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(Color.brandFill, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(switchingTo != nil)
            .accessibilityLabel("Switch to the \((option.trains.first?.scheduledDeparture ?? option.departure).ukClock)")
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        guard let start = journey.replanStart(before: index), let destination = journey.destinationStation else {
            phase = .loaded([])
            return
        }
        phase = .loading

        do {
            let found = try await JourneyPlanner.shared.onwardJourneys(from: start.station, to: destination, arrivingAt: start.time)
            let missed = journey.legs.indices.contains(start.from) ? journey.legs[start.from].service : nil
            // A train from the same station needs the time any change does
            let earliest = start.time.addingTimeInterval(TimeInterval((JourneyConnection.minimumMinutes + JourneyOptions.current.extraChangeMinutes) * 60))

            let candidates = found.filter { option in
                guard let first = option.trains.first else { return false }
                if first.originCRS == start.station.crs, first.expectedDeparture < earliest { return false }
                // Not the train the change is already onto
                return missed.map { !DarwinServiceAdapter(planned: first).isSameJourney(as: $0) } ?? true
            }
            let options = await Self.running(Array(candidates.prefix(5)))
            if Task.isCancelled { return }
            phase = .loaded(Array(options.prefix(3)))
        } catch {
            // The page was closed mid-search: nothing to show the answer to
            if Task.isCancelled { return }
            phase = .failed(JourneyPlanner.message(for: error))
        }
    }

    /// The options whose trains the live feed does not report as cancelled. The planner's
    /// timetable can lag behind a cancellation made on the day, and a train that no longer
    /// reaches the destination is no way to get there. A train too far ahead for the live
    /// feed to list is taken on trust.
    private static func running(_ options: [PlannedJourney]) async -> [PlannedJourney] {
        await withTaskGroup(of: (Int, Bool).self) { group in
            for (position, option) in options.enumerated() {
                group.addTask {
                    for leg in option.trains {
                        if let live = await DarwinService.shared.refreshed(DarwinServiceAdapter(planned: leg)), live.isCancelledService {
                            return (position, false)
                        }
                    }
                    return (position, true)
                }
            }
            var isRunning = [Bool](repeating: true, count: options.count)
            for await (position, running) in group {
                isRunning[position] = running
            }
            return options.enumerated().filter { isRunning[$0.offset] }.map(\.element)
        }
    }

    private func take(_ option: PlannedJourney) async {
        guard let start = journey.replanStart(before: index), let connection = journey.connection(before: index) else { return }
        // Whose train went wrong: the one cancelled, or the one too late for the change
        let cause = connection.departing.isCancelledService && !connection.arriving.isCancelledService
            ? connection.departing.atocCode
            : connection.arriving.atocCode
        switchingTo = option.id
        await option.replace(journey, from: start.from, causedBy: cause, in: modelContext)
        switchingTo = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// A walk or a ride at either end of a journey.
struct JourneyNoteRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.walk")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.brand)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// One train of a journey that is still to run, on the journey's page.
private struct JourneyLegCard: View {
    let train: DarwinServiceAdapter

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    OperatorSummary(operators: [train].operators, compact: true)
                    Spacer(minLength: 8)
                    StatusPill(train.trainStatus)
                }
                // One height whichever logo it is, so the cards line up
                .frame(height: 24)

                Text("\(UKStation.name(for: train.userSearchOriginCRS ?? train.originCRS)) to \(UKStation.name(for: train.userSearchDestinationCRS ?? train.destinationCRS))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(train.realtimeDeparture)
                        .foregroundStyle(train.departureDelayMinutes > 0 ? Color.statusDelayed : Color.ink)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.inkTertiary)
                    Text(train.userSearchDestinationArrivalTime ?? train.userSearchDestinationScheduledArrivalTime ?? "--:--")
                        .foregroundStyle(train.arrivalDelayMinutes > 0 ? Color.statusDelayed : Color.ink)
                    Spacer(minLength: 8)
                    Label("Platform \(train.platform)", systemImage: "signpost.right.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                }
                .font(.headline)
                .monospacedDigit()
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.inkTertiary)
        }
        .padding(16)
        .cardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(train.spokenSummary)
        .accessibilityHint("Shows this train")
    }
}

// MARK: - A Journey of Several Trains

/// A journey train by train: what its one card on My Trains, or its one row in Rail
/// History, opens. A sheet from My Trains; pushed from Rail History once the journey is over.
struct JourneyDetailView: View {
    let journeyID: String
    /// True when pushed from Rail History
    var isHistory = false
    /// Set from My Trains: called with the journey's last train to add the one after it
    var onAddNext: ((SavedTrain) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var savedTrains: [SavedTrain]

    @State private var confirmingRemoval = false

    private var journey: SavedJourney {
        SavedJourney(
            id: journeyID,
            legs: savedTrains
                .filter { $0.journeyID == journeyID && $0.service != nil }
                .sorted { $0.legIndex < $1.legIndex }
        )
    }

    var body: some View {
        let journey = journey

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetHeader(journey.title, eyebrow: eyebrow(journey)) {
                    if !isHistory {
                        HStack(spacing: 10) {
                            ShareLink(item: journey.shareMessage()) {
                                Label("Share journey", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.icon)

                            // One activity for the whole journey, which moves on from train to train
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                LiveActivityManager.shared.startTracking(journey: journey)
                            } label: {
                                Label("Start Live Activity", systemImage: "livephoto")
                            }
                            .buttonStyle(.icon)
                        }
                    }
                }
                // As a sheet, clear of the drag indicator; pushed, the bar is above
                .padding(.top, isHistory ? 0 : 24)

                summaryCard(journey)

                if !isHistory {
                    DisruptionsCard(trains: journey.services)
                }

                SectionLabel(journey.legs.count == 1 ? "Your train" : "Your trains")
                    .padding(.top, 4)

                // Getting to the first train, when that takes more than turning up
                if let opening = journey.legs.first?.transferNote {
                    JourneyNoteRow(text: opening)
                }

                ForEach(Array(journey.legs.enumerated()), id: \.element.persistentModelID) { index, leg in
                    if let connection = journey.connection(before: index) {
                        ConnectionRow(connection: connection)

                        // A change in doubt comes with the ways to carry on without it
                        if !isHistory, !leg.isPast, needsAnotherWay(connection) {
                            OnwardOptionsCard(journey: journey, index: index)
                        }
                    }
                    legLink(leg)
                }

                if let onward = journey.legs.last?.onwardNote {
                    JourneyNoteRow(text: onward)
                }

                if isHistory, let claim = journey.delayRepay {
                    DelayRepaySection(train: claim.train, claim: claim.claim)
                        .padding(.top, 4)
                }

                if !isHistory, let onAddNext, let last = journey.legs.last, last.nextTrainStart != nil {
                    Button {
                        onAddNext(last)
                    } label: {
                        Label("Add Next Train", systemImage: "arrow.triangle.branch")
                    }
                    .buttonStyle(.secondary)
                    .padding(.top, 4)
                }

                if !isHistory {
                    Button("Remove Journey from My Trains", role: .destructive) {
                        confirmingRemoval = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            // In Rail History the tab bar floats over the end of the page
            .padding(.bottom, isHistory ? 96 : 32)
        }
        .background(Color.surface)
        .navigationBarTitleDisplayMode(.inline)
        // The sheet has its own header, and nothing to go back to
        .toolbar(isHistory ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            if isHistory {
                ToolbarItem(placement: .primaryAction) {
                    Button("Remove from Rail History", systemImage: "trash") {
                        confirmingRemoval = true
                    }
                }
            }
        }
        .confirmationDialog(
            isHistory ? "Remove this journey from Rail History?" : "Remove this journey from My Trains?",
            isPresented: $confirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                // From My Trains only the trains still to run go: one that has run is history
                remove(isHistory ? journey.legs : journey.legs.filter { !$0.isPast })
                dismiss()
            }
        }
        // The last of its trains was removed from a train's own screen
        .onChange(of: journey.legs.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
    }

    // MARK: Pieces

    /// True when the change may not be made, or cannot be: a tight one while it is still to
    /// come, and a missed or cancelled one for as long as its train is being followed.
    private func needsAnotherWay(_ connection: JourneyConnection) -> Bool {
        switch connection.state {
        case .comfortable: return false
        case .tight: return connection.isAhead()
        case .missed, .broken: return true
        }
    }

    /// "Tomorrow · 2 trains", or the day a past journey was made
    private func eyebrow(_ journey: SavedJourney) -> String {
        let day: String
        if isHistory {
            let finished = journey.legs.map { $0.movedToPastAt ?? $0.addedAt }.max() ?? Date()
            day = finished.formatted(date: .abbreviated, time: .omitted)
        } else {
            day = journey.services.first?.dayLabel() ?? "Today"
        }
        return "\(day) · \(journey.legs.count == 1 ? "1 train" : "\(journey.legs.count) trains")"
    }

    /// How the journey is going, or how it went.
    private func headline(_ journey: SavedJourney) -> (label: String, color: Color) {
        guard isHistory else { return journey.status }
        if journey.services.contains(where: \.isCancelledService) { return ("Disrupted", .statusCancelled) }
        let late = journey.minutesLate
        if late > 0 { return ("Arrived \(TravelStats.duration(minutes: late)) late", .statusDelayed) }
        return ("On time", .statusOnTime)
    }

    private func summaryCard(_ journey: SavedJourney) -> some View {
        let headline = headline(journey)
        let first = journey.services.first
        let last = journey.services.last
        let arrival = last?.userSearchDestinationArrivalTime ?? last?.userSearchDestinationScheduledArrivalTime ?? "--:--"

        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "tram.fill")
                        .font(.title3.weight(.semibold))
                        .accessibilityHidden(true)
                    Text(headline.label)
                        .font(.title2.weight(.bold))
                }
                .foregroundStyle(headline.color)

                HStack(spacing: 8) {
                    Text(first?.realtimeDeparture ?? "--:--")
                    Image(systemName: "arrow.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.inkTertiary)
                        .accessibilityHidden(true)
                    Text(arrival)
                    Spacer(minLength: 8)
                    OperatorSummary(operators: journey.services.operators, compact: true)
                }
                .font(.headline)
                .foregroundStyle(Color.ink)
                .monospacedDigit()

                Text(journey.legs.count > 1 ? journey.changesText : "Direct")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)

                // After a change of plan, how far behind the first plan the journey now is
                if journey.disruptedBy != nil, journey.minutesLate > 0, let planned = journey.plannedArrival {
                    Text("\(TravelStats.duration(minutes: journey.minutesLate)) later than first planned (\(planned.ukClock))")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.statusDelayed)
                }

                // What needs attention, said in full
                if !isHistory, let risk = journey.connectionAtRisk() {
                    Label("\(risk.title): \(risk.detail.prefix(1).lowercased() + risk.detail.dropFirst())", systemImage: risk.systemImage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(risk.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A train of the journey, opening that train's own screen.
    @ViewBuilder
    private func legLink(_ leg: SavedTrain) -> some View {
        if let service = leg.service {
            if isHistory {
                // Rail History's own page for a train, on the stack this page was pushed onto
                NavigationLink(value: leg) {
                    PastJourneyRow(train: leg, service: service, isLeg: true)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    JourneyLegScreen(leg: leg) { remove([leg]) }
                } label: {
                    if leg.isPast {
                        PastJourneyRow(train: leg, service: service, isLeg: true)
                    } else {
                        JourneyLegCard(train: service)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func remove(_ legs: [SavedTrain]) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        for leg in legs {
            if !leg.isPast, let service = leg.service {
                LiveActivityManager.shared.endTracking(for: service)
            }
            modelContext.delete(leg)
        }
        try? modelContext.save()
        // The journey's Live Activity ends with the last of its trains
        LiveActivityManager.shared.updateJourney(with: savedTrains)
    }
}

/// One train of a journey on the screen a train followed on its own has, kept up to date
/// while it is open.
private struct JourneyLegScreen: View {
    let leg: SavedTrain
    var onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Removing the train leaves this screen on show while it slides away
        if leg.modelContext != nil, !leg.isDeleted, let service = leg.service {
            if leg.isPast {
                RailHistoryDetailView(train: leg)
            } else {
                JourneyDashboardView(
                    journey: service.toTrainJourney(),
                    rawService: service,
                    onRemove: {
                        dismiss()
                        onRemove()
                    },
                    // The page this was pushed from already sets out the journey
                    isPushed: true,
                    showsJourney: false
                )
            }
        }
    }
}

// MARK: - Your Journey (on a followed train)

/// On a followed train that came from a journey plan and has a walk or a ride at either
/// end of it. A journey of several trains has a page of its own instead.
struct JourneyLegsCard: View {
    /// The train whose screen this is
    let train: DarwinServiceAdapter

    @Query private var savedTrains: [SavedTrain]

    private var journey: SavedJourney? {
        guard let record = savedTrains.first(where: { $0.service?.isSameJourney(as: train) == true }),
              let journey = SavedJourney(containing: record, in: savedTrains), journey.isWorthShowing else { return nil }
        return journey
    }

    var body: some View {
        if let journey {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("Your journey", systemImage: "arrow.triangle.swap")

                    Text(journey.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ink)

                    VStack(alignment: .leading, spacing: 10) {
                        if let opening = journey.legs.first?.transferNote {
                            JourneyNoteRow(text: opening)
                        }

                        ForEach(Array(journey.legs.enumerated()), id: \.element.persistentModelID) { index, leg in
                            if let connection = journey.connection(before: index) {
                                ConnectionRow(connection: connection)
                            }
                            if let service = leg.service {
                                legRow(service, isCurrent: service.isSameJourney(as: train), isPast: leg.isPast)
                            }
                        }

                        if let onward = journey.legs.last?.onwardNote {
                            JourneyNoteRow(text: onward)
                        }
                    }
                }
            }
        }
    }

    private func legRow(_ leg: DarwinServiceAdapter, isCurrent: Bool, isPast: Bool) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isCurrent ? Color.brand : Color.track)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(UKStation.name(for: leg.userSearchOriginCRS ?? leg.originCRS)) to \(UKStation.name(for: leg.userSearchDestinationCRS ?? leg.destinationCRS))")
                    .font(.subheadline.weight(isCurrent ? .bold : .medium))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.leading)
                Text("\(leg.realtimeDeparture) → \(leg.userSearchDestinationArrivalTime ?? leg.userSearchDestinationScheduledArrivalTime ?? "--:--")\(isCurrent ? " · This train" : "")")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            StatusPill(isPast && !leg.isCancelledService ? "Done" : leg.trainStatus.label, color: isPast && !leg.isCancelledService ? .inkSecondary : leg.trainStatus.color)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
