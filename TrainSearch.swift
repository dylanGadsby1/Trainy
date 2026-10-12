import Foundation

// MARK: - Train Search
// One search over both feeds. Darwin has live data but only lists trains up to about
// four hours ahead; Realtime Trains has the timetable for any date. A train inside
// Darwin's reach comes back from both, so the two lists are merged into one.

enum TrainSearch {

    /// How many minutes of timetable to fetch from `date` onwards.
    static let windowMinutes = 360

    /// Trains from `origin` to `destination` leaving at or after `date`, earliest first.
    /// Either feed can fail without failing the search; it throws only when no feed answered.
    static func departures(from origin: String, to destination: String, at date: Date) async throws -> [DarwinServiceAdapter] {
        // Neither feed is asked about the past: an earlier time means "from now"
        let start = max(date, Date())

        async let live = attempt { try await DarwinService.shared.search(from: origin, to: destination, at: start) }
        async let timetable = attempt {
            try await RTTService.shared.search(from: origin, to: destination, at: start, window: windowMinutes)
        }

        switch await (live, timetable) {
        case (.success(let live), .success(let timetable)):
            return merge(live: live, timetable: timetable)
        case (.success(let live), .failure(let error)):
            // Beyond Darwin's reach the timetable is the only source, so its failure is the search's
            if live.isEmpty { throw error }
            return merge(live: live, timetable: [])
        case (.failure, .success(let timetable)):
            return merge(live: [], timetable: timetable)
        case (.failure(let error), .failure):
            throw error
        }
    }

    /// Combines the two feeds without listing any train twice. The Darwin entry is kept,
    /// because it is live, and takes the Realtime Trains identity of its twin.
    static func merge(live: [DarwinServiceAdapter], timetable: [DarwinServiceAdapter]) -> [DarwinServiceAdapter] {
        var merged = live

        for train in timetable {
            if let index = merged.firstIndex(where: { $0.isSameJourney(as: train) }) {
                if merged[index].rttIdentity == nil {
                    merged[index].rttIdentity = train.rttIdentity
                }
            } else {
                merged.append(train)
            }
        }

        return merged.sorted {
            let first = $0.scheduledDepartureDate ?? .distantFuture
            let second = $1.scheduledDepartureDate ?? .distantFuture
            return first == second ? $0.id < $1.id : first < second
        }
    }

    private static func attempt<T>(_ work: () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await work())
        } catch {
            return .failure(error)
        }
    }
}
