import SwiftUI
import SwiftData

// MARK: - Alternative Trains
// When a followed train is cancelled or running late, the other trains on the same route
// that would get the user there sooner, each with a button that follows it instead.

enum AlternativeTrains {

    /// A train this late, and not yet gone, is worth looking past
    static let delayThreshold = 10

    /// A cancelled train stops being worth replacing this long after it should have left
    static let cancelledWindow: TimeInterval = 2 * 3600

    static let limit = 3

    /// How far before the train's scheduled time the search for others starts
    static let lookBack: TimeInterval = 30 * 60

    /// True while another train might serve the user better than `train`.
    static func areWorthOffering(for train: DarwinServiceAdapter, now: Date = Date()) -> Bool {
        guard train.hasArrived != true else { return false }

        if train.isCancelledService {
            guard let departure = train.scheduledDepartureDate else { return false }
            return now.timeIntervalSince(departure) < cancelledWindow
        }

        guard train.hasUnknownDelay == true || train.delayMinutes >= delayThreshold else { return false }
        // Once the user is on the train there is nothing to switch to
        if train.stops?.first?.hasCalled == true { return false }
        if train.hasUnknownDelay == true { return true }
        return (train.expectedDepartureDate ?? .distantPast) > now
    }

    /// The trains from `candidates` to offer in place of `train`: still to leave, running,
    /// and due in before `train` is (when that is known). Soonest arrival first.
    static func choose(from candidates: [DarwinServiceAdapter], insteadOf train: DarwinServiceAdapter, now: Date = Date()) -> [DarwinServiceAdapter] {
        // A cancelled train never arrives, and a train with no new time might not for a while
        let deadline = train.isCancelledService || train.hasUnknownDelay == true ? nil : train.expectedArrivalDate

        return candidates
            .filter { candidate in
                guard !candidate.isSameJourney(as: train), !candidate.isCancelledService,
                      let departure = candidate.expectedDepartureDate, departure > now else { return false }
                guard let deadline else { return true }
                guard let arrival = candidate.expectedArrivalDate else { return false }
                return arrival < deadline
            }
            .sorted {
                let first = $0.expectedArrivalDate ?? $0.expectedDepartureDate ?? .distantFuture
                let second = $1.expectedArrivalDate ?? $1.expectedDepartureDate ?? .distantFuture
                return first < second
            }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Card

struct AlternativeTrainsCard: View {
    /// The train that is cancelled or late
    let train: DarwinServiceAdapter
    /// Called once the user has switched to another train
    var onSwitched: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Query private var savedTrains: [SavedTrain]

    private enum Phase {
        case loading
        case loaded([DarwinServiceAdapter])
        case failed(String)
    }

    @State private var phase = Phase.loading

    /// The saved copy of `train`, which a switch replaces
    private var original: SavedTrain? {
        savedTrains.first { $0.service?.isSameJourney(as: train) == true }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Other trains", systemImage: "arrow.triangle.branch")

                switch phase {
                case .loading:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Looking for other trains…")
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

                case .loaded(let trains) where trains.isEmpty:
                    Text(train.isCancelledService
                         ? "No other trains on this route are listed for the next few hours."
                         : "No other train is due in sooner. Yours is still the first to arrive.")
                        .font(.subheadline)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                case .loaded(let trains):
                    VStack(spacing: 0) {
                        ForEach(Array(trains.enumerated()), id: \.element.id) { index, alternative in
                            if index > 0 { Divider() }
                            row(alternative)
                        }
                    }
                }
            }
        }
        // Once per train and state: a search costs requests that both feeds ration
        .task(id: "\(train.journeyKey).\(train.isCancelledService)") {
            await load()
        }
    }

    private func row(_ alternative: DarwinServiceAdapter) -> some View {
        let isFollowed = savedTrains.contains { !$0.isPast && $0.service?.isSameJourney(as: alternative) == true }
        let facts = [
            gain(of: alternative),
            alternative.delayMinutes > 0 ? "\(alternative.delayMinutes) min late" : nil,
            alternative.platform == "TBC" ? "Platform TBC" : "Platform \(alternative.platform)"
        ]
            .compactMap { $0 }
            .joined(separator: " · ")

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(alternative.realtimeDeparture)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.inkTertiary)
                    Text(alternative.userSearchDestinationArrivalTime ?? alternative.userSearchDestinationScheduledArrivalTime ?? "--:--")
                }
                .font(.headline)
                // An alternative that is itself running late shows its new times in the delay colour
                .foregroundStyle(alternative.delayMinutes > 0 ? Color.statusDelayed : Color.ink)
                .monospacedDigit()

                Text(facts)
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(alternative.spokenSummary)

            Spacer(minLength: 8)

            Button {
                switchTo(alternative)
            } label: {
                Text(isFollowed ? "Following" : "Switch")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isFollowed ? Color.inkSecondary : Color.onBrand)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 34)
                    .background(isFollowed ? Color.subtleFill : Color.brandFill, in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isFollowed)
            .accessibilityLabel(isFollowed ? "Following this train" : "Switch to the \(alternative.realtimeDeparture)")
        }
        .padding(.vertical, 4)
    }

    /// How much sooner `alternative` is due in than the late train: "12 min sooner".
    private func gain(of alternative: DarwinServiceAdapter) -> String? {
        guard !train.isCancelledService, train.hasUnknownDelay != true,
              let mine = train.expectedArrivalDate, let theirs = alternative.expectedArrivalDate else { return nil }
        let minutes = Int(mine.timeIntervalSince(theirs) / 60)
        return minutes > 0 ? "\(minutes) min sooner" : nil
    }

    private func load() async {
        phase = .loading
        let origin = train.userSearchOriginCRS ?? train.originCRS
        let destination = train.userSearchDestinationCRS ?? train.destinationCRS

        // From a little before the train's own time: an earlier train that is itself running
        // late may not have left yet. The search never looks back past the present.
        let start = (train.scheduledDepartureDate ?? Date()).addingTimeInterval(-AlternativeTrains.lookBack)

        do {
            let trains = try await TrainSearch.departures(from: origin, to: destination, at: start)
            phase = .loaded(AlternativeTrains.choose(from: trains, insteadOf: train))
        } catch {
            // The screen was closed mid-search: nothing to show the answer to
            if Task.isCancelled { return }
            phase = .failed(TrainSearch.message(for: error))
        }
    }

    /// Follows `alternative` in place of the train this card is about. A cancelled train is
    /// kept, in Rail History, where its Delay Repay claim is; a late one the user is no
    /// longer catching is dropped.
    private func switchTo(_ alternative: DarwinServiceAdapter) {
        guard let data = try? JSONEncoder().encode(alternative) else { return }
        let replacement = SavedTrain(id: alternative.id, serviceData: data)
        modelContext.insert(replacement)

        if let original, !original.isPast {
            // On a journey with a change, the new train takes the old one's place in it
            replacement.journeyID = original.journeyID
            replacement.legIndex = original.legIndex
            replacement.journeyTitle = original.journeyTitle
            replacement.transferNote = original.transferNote
            replacement.transferMinutes = original.transferMinutes
            replacement.onwardNote = original.onwardNote

            LiveActivityManager.shared.endTracking(for: train)
            if train.isCancelledService {
                original.journeyID = nil
                original.isPast = true
                original.movedToPastAt = Date()
            } else {
                modelContext.delete(original)
            }
        }

        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSwitched()
    }
}
