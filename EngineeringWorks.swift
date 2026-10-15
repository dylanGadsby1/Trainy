import Foundation
import CoreLocation

// MARK: - Engineering Works
// Planned closures and rail replacement buses, from the National Rail Knowledgebase
// incidents feed on the Rail Data Marketplace, matched to the user's saved routes so they hear
// about a weekend's works days ahead.
//
// The feed names the affected line in words, "Between Bedford / Luton and Sutton", not as a
// list of stations. So a work is matched by the stations it names, the operators it lists and
// the route's path along the tracks: good, but now and then it warns about works that do not
// touch the route, or misses some that do.

/// One planned work from the feed, cut down to what the app shows and matches on.
struct EngineeringWork: Codable, Hashable, Identifiable {
    /// The feed's IncidentNumber
    let id: String
    let start: Date
    /// Nil when it runs until further notice
    let end: Date?
    /// "Buses replace trains between Corkickle and Whitehaven until further notice"
    let summary: String
    /// "Between London Bridge and Sutton"
    let routesAffected: String
    /// Two-letter operator codes, "TL"
    let operators: [String]
    /// The work's page on the National Rail website
    let link: URL?

    func overlaps(from: Date, to: Date) -> Bool {
        start < to && (end ?? .distantFuture) > from
    }

    /// "Sat 17 Oct", "Sat 17 – Sun 18 Oct", or "Until further notice" for one already running
    /// with no end. In UK time, as the works are.
    func whenText(now: Date = Date()) -> String {
        let calendar = SavedRoute.ukCalendar
        let day = Date.FormatStyle(timeZone: calendar.timeZone).weekday(.abbreviated).day()
        let dayMonth = Date.FormatStyle(timeZone: calendar.timeZone).weekday(.abbreviated).day().month(.abbreviated)

        guard let end else {
            return start <= now ? "Until further notice" : "From \(start.formatted(dayMonth))"
        }
        // An end at midnight belongs to the day before
        let lastDay = end.addingTimeInterval(-1)
        if start <= now {
            return "Until \(lastDay.formatted(dayMonth))"
        }
        if calendar.isDate(start, inSameDayAs: lastDay) {
            return start.formatted(dayMonth)
        }
        let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: lastDay)
        return "\(start.formatted(sameMonth ? day : dayMonth)) – \(lastDay.formatted(dayMonth))"
    }
}

// MARK: - Feed

enum EngineeringWorksFeed {

    static let endpoint = URL(string: "https://api1.raildata.org.uk/1010-knowlegebase-incidents-xml-feed1_0/incidents.xml")!

    /// The planned works in a download of the feed. The marketplace sends it gzipped without
    /// saying so, so URLSession leaves it packed; plain XML is accepted too.
    static func works(in data: Data) -> [EngineeringWork]? {
        let xml = gunzipped(data) ?? data
        let parser = XMLParser(data: xml)
        let delegate = IncidentParser()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        guard parser.parse() else { return nil }
        return delegate.works
    }

    /// Unpacks gzip (RFC 1952). Nil when `data` is not gzip.
    static func gunzipped(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var index = 10
        if flags & 0x04 != 0 {
            index += 2 + (Int(bytes[index]) | Int(bytes[index + 1]) << 8)
        }
        // A file name, then a comment, each ending in a zero byte
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            index += 1
        }
        if flags & 0x02 != 0 { index += 2 }
        // Eight bytes at the end hold a checksum and the length
        guard index < bytes.count - 8 else { return nil }
        let deflated = Data(bytes[index..<(bytes.count - 8)])
        // Compression's zlib is raw DEFLATE, which is what gzip wraps
        return try? (deflated as NSData).decompressed(using: .zlib) as Data
    }

    /// Text with its markup taken out: the feed's free text is HTML.
    static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, character) in ["&nbsp;": " ", "&#39;": "'", "&rsquo;": "’", "&quot;": "\"", "&lt;": "<", "&gt;": ">", "&amp;": "&"] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    /// Reads each PtIncident's few fields that matter, keeping the planned ones still in force.
    private final class IncidentParser: NSObject, XMLParserDelegate {
        var works: [EngineeringWork] = []
        private var fields: [String: String] = [:]
        private var operators: [String] = []
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            if elementName == "PtIncident" {
                fields = [:]
                operators = []
            }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            text += String(decoding: CDATABlock, as: UTF8.self)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            text = ""
            switch elementName {
            case "PtIncident":
                if let work = makeWork() { works.append(work) }
            case "OperatorRef":
                if !value.isEmpty { operators.append(value) }
            case "Uri":
                // The first link is the work's own page
                if fields["Uri"] == nil { fields["Uri"] = value }
            default:
                fields[elementName] = value
            }
        }

        private func makeWork() -> EngineeringWork? {
            // "Amended 22:49 London Paddington to Swansea": changes to a train's times, not works on the line
            guard fields["Planned"] == "true", fields["ClearedIncident"] != "true",
                  // A work called off stays in the feed as "CANCELLED: Engineering work in the Arlesey area"
                  fields["Summary"].map({ !$0.hasPrefix("Amended") && !$0.uppercased().hasPrefix("CANCELLED") }) ?? false,
                  let id = fields["IncidentNumber"], !id.isEmpty,
                  let start = EngineeringWorksFeed.date(fields["StartTime"]) else { return nil }
            return EngineeringWork(
                id: id,
                start: start,
                end: EngineeringWorksFeed.date(fields["EndTime"]),
                summary: EngineeringWorksFeed.plainText(fields["Summary"] ?? ""),
                routesAffected: EngineeringWorksFeed.plainText(fields["RoutesAffected"] ?? ""),
                operators: operators,
                link: fields["Uri"].flatMap(URL.init(string:))
            )
        }
    }
}

// MARK: - Places Named

/// Finds the stations in the feed's words for where a work is.
struct StationNames {

    private let index: [String: UKStation]

    init(_ stations: [UKStation]) {
        var index: [String: UKStation] = [:]
        for station in stations {
            index[Self.normalised(station.name)] = station
        }
        // The feed's shorter names: "Sutton" for "Sutton (London)", "Lincoln" for "Lincoln
        // Central", "Heathrow Terminal 4" for "Heathrow Terminal 4 Rail". Never over a real name.
        for station in stations {
            let name = Self.normalised(station.name)
            for alias in [
                name.replacingOccurrences(of: " \\(.*\\)$", with: "", options: .regularExpression),
                name.replacingOccurrences(of: " central$", with: "", options: .regularExpression),
                name.replacingOccurrences(of: " rail$", with: "", options: .regularExpression)
            ] where alias != name && index[alias] == nil {
                index[alias] = station
            }
        }
        if index["heathrow airport"] == nil, let heathrow = stations.first(where: { $0.crs == "HXX" }) {
            index["heathrow airport"] = heathrow
        }
        self.index = index
    }

    /// Where a work is, from the feed's words: "Buses replace trains between Doncaster and Hull
    /// on Saturday 17 October", or "No trains to / from Salford Central".
    func places(in text: String) -> WorkPlaces {
        var places = WorkPlaces()
        let range = NSRange(text.startIndex..., in: text)
        for match in Self.between.matches(in: text, range: range) {
            guard let from = Range(match.range(at: 1), in: text), let to = Range(match.range(at: 2), in: text) else { continue }
            let ends = (stations(in: text[from]), stations(in: text[to]))
            if !ends.0.isEmpty, !ends.1.isEmpty { places.stretches.append(ends) }
        }
        if places.stretches.isEmpty {
            places.stations = stations(in: text[...])
        }
        return places
    }

    /// "between A / B and C", up to where the sentence moves on to when, or to the next stretch
    private static let between = try! NSRegularExpression(
        pattern: "\\bbetween\\s+(.+?)\\s+and\\s+(.+?)(?=\\s*(?:$|[,;:.]|\\s(?:and\\s+(?:also\\s+)?between|on|from|until|during|for|while|at|due|with|as|in|throughout|after|before|this|every|each|starting|between|via|because)\\b))",
        options: .caseInsensitive
    )

    private static let separators = try! NSRegularExpression(
        pattern: "\\s*(?:/|,|;|\\band\\b|\\bor\\b|\\bto\\b|\\bfrom\\b|\\bvia\\b|\\bbetween\\b|\\bincluding\\b)\\s*",
        options: .caseInsensitive
    )

    /// Words after which a sentence goes on to say when: "Guildford on Sunday 18 October"
    private static let whenWords: Set<Substring> = ["on", "until", "during", "for", "while", "at", "due", "with", "as", "in", "throughout", "after", "before", "this", "every", "each", "starting", "because"]

    private func stations(in text: Substring) -> [UKStation] {
        let text = String(text)
        var pieces: [String] = []
        var last = text.startIndex
        for match in Self.separators.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            pieces.append(String(text[last..<range.lowerBound]))
            last = range.upperBound
        }
        pieces.append(String(text[last...]))

        var found: [UKStation] = []
        for piece in pieces {
            if let station = station(named: piece), !found.contains(station) {
                found.append(station)
            }
        }
        return found
    }

    /// A station by name, letting words in front go ("South Western Railway London Waterloo")
    /// and the words saying when ("Guildford on Sunday 18 October"). The whole piece is tried
    /// first, so "Kirkby in Ashfield" stays one station.
    private func station(named piece: String) -> UKStation? {
        let words = Self.normalised(piece).split(separator: " ")
        let ends = [words.count] + words.indices.reversed().filter { $0 > 0 && Self.whenWords.contains(words[$0]) }
        for end in ends {
            for first in 0..<end {
                let candidate = words[first..<end].joined(separator: " ")
                if candidate.count >= 4, let station = index[candidate] { return station }
            }
        }
        return nil
    }

    private static func normalised(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "[’'.]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Where a work is: stretches of line between two stations, or failing those, single stations.
struct WorkPlaces {
    /// Each stretch runs from any station of the first group to any of the second
    var stretches: [([UKStation], [UKStation])] = []
    var stations: [UKStation] = []

    var isEmpty: Bool { stretches.isEmpty && stations.isEmpty }
}

// MARK: - Matching

/// What is known of the way a saved route runs, from the journey planner: kept so works can
/// be matched without asking again.
struct RouteProfile: Codable {
    /// The tracks of the likeliest ways between the two stations, as encoded polylines
    var lines: [String]
    /// Every station those ways call at, by CRS
    var stations: [String]
    /// The operators that run them, by two-letter code
    var operators: [String]
    var fetched: Date
}

enum EngineeringWorksMatcher {

    /// Whether `work` is on the route between `origin` and `destination`. A route the planner
    /// could not describe is taken to be a straight line between its two stations.
    /// Where `work` is: the summary says it best ("no trains between Bedwyn and Pewsey"); the
    /// routes affected list every service it touches ("between London Paddington and Penzance").
    static func places(of work: EngineeringWork, names: StationNames) -> WorkPlaces {
        let summary = names.places(in: work.summary)
        return summary.isEmpty ? names.places(in: work.routesAffected) : summary
    }

    static func work(_ work: EngineeringWork, places: WorkPlaces, affects profile: RouteProfile?, origin: UKStation, destination: UKStation) -> Bool {
        if let operators = profile?.operators, !operators.isEmpty, Set(work.operators).isDisjoint(with: operators) {
            return false
        }
        // "Various Southeastern routes": the operator is all there is to go on
        guard !places.isEmpty else { return true }

        let lines = (profile?.lines ?? []).map { densified(RouteLine.line($0).coordinates) }
        let tracks = lines.isEmpty ? [densified([origin.coordinate, destination.coordinate])] : lines
        let calls = Set(profile?.stations ?? []).union([origin.crs, destination.crs])

        for (froms, tos) in places.stretches {
            for from in froms {
                for to in tos where tracks.contains(where: { overlap($0, from: from.coordinate, to: to.coordinate) }) {
                    return true
                }
            }
        }
        // Single stations: the work is at the station, or on all services to and from it
        return places.stations.contains { station in
            calls.contains(station.crs) || tracks.contains { track in
                track.contains { RouteLine.metres(from: $0, to: station.coordinate) < 1_000 }
            }
        }
    }

    /// Whether a fair stretch of `track` runs between `a` and `b`: inside the narrow ellipse
    /// with the two stations at its ends. Touching it only at one end is not enough, so works
    /// "between London Paddington and Reading" are not put on a route from Reading westwards.
    static func overlap(_ track: [CLLocationCoordinate2D], from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Bool {
        let span = RouteLine.metres(from: a, to: b)
        // Railways wander a little, and a station's point can be off its tracks: half a kilometre
        // more. Wider than this and a route leaving one end of the stretch on another line counts.
        let limit = span * 1.05 + 500
        let needed = min(5_000, max(300, span * 0.3))

        func inside(_ point: CLLocationCoordinate2D) -> Bool {
            RouteLine.metres(from: point, to: a) + RouteLine.metres(from: point, to: b) <= limit
        }

        var length = 0.0
        for (start, end) in zip(track, track.dropFirst()) where inside(start) && inside(end) {
            length += RouteLine.metres(from: start, to: end)
            if length >= needed { return true }
        }
        return false
    }

    /// The line with a point at least every 250 metres, so a long straight is not skipped over.
    static func densified(_ line: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard var previous = line.first else { return [] }
        var points = [previous]
        for point in line.dropFirst() {
            let steps = Int(RouteLine.metres(from: previous, to: point) / 250)
            if steps > 1 {
                for step in 1..<steps {
                    let part = Double(step) / Double(steps)
                    points.append(CLLocationCoordinate2D(
                        latitude: previous.latitude + (point.latitude - previous.latitude) * part,
                        longitude: previous.longitude + (point.longitude - previous.longitude) * part
                    ))
                }
            }
            points.append(point)
            previous = point
        }
        return points
    }
}
