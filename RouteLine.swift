import Foundation
import CoreLocation

// MARK: - Route Line
// The path a train takes along the tracks between the stations where the traveller boards
// and leaves it. It comes from the journey planner (JourneyPlanner.swift), is thinned, and
// is kept with the train as an encoded polyline, so the map can draw the journey where it
// really runs instead of in straight lines between stops.

enum RouteLine {

    /// A decoded line, with how far along it each point is, in metres
    final class Line {
        let coordinates: [CLLocationCoordinate2D]
        let distances: [Double]

        init(_ coordinates: [CLLocationCoordinate2D]) {
            self.coordinates = coordinates
            var total = 0.0
            var distances = [0.0]
            for (start, end) in zip(coordinates, coordinates.dropFirst()) {
                total += RouteLine.metres(from: start, to: end)
                distances.append(total)
            }
            self.distances = coordinates.isEmpty ? [] : distances
        }

        var length: Double { distances.last ?? 0 }

        /// How far along the line the point nearest `coordinate` is, looking no earlier than `minimum`.
        func distance(nearestTo coordinate: CLLocationCoordinate2D, from minimum: Double = 0) -> Double {
            var best = minimum
            var bestGap = Double.greatestFiniteMagnitude
            for (index, point) in coordinates.enumerated() where distances[index] >= minimum {
                let gap = RouteLine.metres(from: point, to: coordinate)
                if gap < bestGap {
                    bestGap = gap
                    best = distances[index]
                }
            }
            return best
        }

        /// The line in two parts at `distance` along it, with the point where it divides.
        func divided(at distance: Double) -> (behind: [CLLocationCoordinate2D], ahead: [CLLocationCoordinate2D], point: CLLocationCoordinate2D)? {
            guard coordinates.count > 1 else { return nil }
            let target = min(max(0, distance), length)
            // The first point at or beyond the target
            let next = max(1, distances.firstIndex { $0 >= target } ?? coordinates.count - 1)
            let start = coordinates[next - 1], end = coordinates[next]
            let span = distances[next] - distances[next - 1]
            let part = span > 0 ? (target - distances[next - 1]) / span : 0
            let point = CLLocationCoordinate2D(
                latitude: start.latitude + (end.latitude - start.latitude) * part,
                longitude: start.longitude + (end.longitude - start.longitude) * part
            )
            return (Array(coordinates[..<next]) + [point], [point] + Array(coordinates[next...]), point)
        }
    }

    /// Decoding a line of several hundred points on every redraw of the map would be wasteful
    private static let cache = NSCache<NSString, Line>()

    /// The line an encoded polyline stands for, as saved with a train.
    static func line(_ encoded: String) -> Line {
        if let cached = cache.object(forKey: encoded as NSString) { return cached }
        let line = Line(decode(encoded, precision: savedPrecision))
        cache.setObject(line, forKey: encoded as NSString)
        return line
    }

    /// Lines are saved to five decimal places, about a metre
    static let savedPrecision = 5

    /// A planner's line, thinned and encoded for keeping. Nil when it is not a line at all.
    static func saved(from encoded: String, precision: Int) -> String? {
        let points = simplify(decode(encoded, precision: precision), tolerance: 12)
        return points.count > 1 ? encode(points, precision: savedPrecision) : nil
    }

    // MARK: - Geometry

    /// Metres between two places that are near each other. Plenty for a railway line.
    static func metres(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let north = (end.latitude - start.latitude) * 111_320
        let east = (end.longitude - start.longitude) * 111_320 * cos(start.latitude * .pi / 180)
        return (north * north + east * east).squareRoot()
    }

    /// Drops the points a line can do without: none of those left out is further than
    /// `tolerance` metres from the line that remains (Douglas–Peucker).
    static func simplify(_ points: [CLLocationCoordinate2D], tolerance: Double) -> [CLLocationCoordinate2D] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var spans = [(0, points.count - 1)]

        while let (first, last) = spans.popLast() {
            guard last > first + 1 else { continue }
            var furthest = first
            var furthestGap = 0.0
            for index in (first + 1)..<last {
                let gap = offset(of: points[index], from: points[first], to: points[last])
                if gap > furthestGap {
                    furthestGap = gap
                    furthest = index
                }
            }
            if furthestGap > tolerance {
                keep[furthest] = true
                spans.append((first, furthest))
                spans.append((furthest, last))
            }
        }
        return zip(points, keep).filter(\.1).map(\.0)
    }

    /// Metres from `point` to the straight line between `start` and `end`.
    private static func offset(of point: CLLocationCoordinate2D, from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let scale = cos(start.latitude * .pi / 180)
        let x = (point.longitude - start.longitude) * scale, y = point.latitude - start.latitude
        let dx = (end.longitude - start.longitude) * scale, dy = end.latitude - start.latitude
        let lengthSquared = dx * dx + dy * dy
        let along = lengthSquared > 0 ? min(1, max(0, (x * dx + y * dy) / lengthSquared)) : 0
        let gapX = x - along * dx, gapY = y - along * dy
        return (gapX * gapX + gapY * gapY).squareRoot() * 111_320
    }

    // MARK: - Encoded Polylines

    static func decode(_ encoded: String, precision: Int) -> [CLLocationCoordinate2D] {
        let factor = pow(10.0, Double(precision))
        var coordinates: [CLLocationCoordinate2D] = []
        var latitude = 0, longitude = 0
        var bytes = encoded.utf8.makeIterator()

        /// The next number in the string, or nil at its end
        func next() -> Int? {
            var result = 0, shift = 0
            while let byte = bytes.next() {
                let value = Int(byte) - 63
                result |= (value & 0x1f) << shift
                shift += 5
                if value < 0x20 {
                    return result & 1 == 1 ? ~(result >> 1) : result >> 1
                }
            }
            return nil
        }

        while let north = next(), let east = next() {
            latitude += north
            longitude += east
            coordinates.append(CLLocationCoordinate2D(latitude: Double(latitude) / factor, longitude: Double(longitude) / factor))
        }
        return coordinates
    }

    static func encode(_ coordinates: [CLLocationCoordinate2D], precision: Int) -> String {
        let factor = pow(10.0, Double(precision))
        var encoded = ""
        var lastLatitude = 0, lastLongitude = 0

        func append(_ value: Int) {
            var number = value < 0 ? ~(value << 1) : value << 1
            while number >= 0x20 {
                encoded.unicodeScalars.append(UnicodeScalar(UInt8((0x20 | (number & 0x1f)) + 63)))
                number >>= 5
            }
            encoded.unicodeScalars.append(UnicodeScalar(UInt8(number + 63)))
        }

        for coordinate in coordinates {
            let latitude = Int((coordinate.latitude * factor).rounded())
            let longitude = Int((coordinate.longitude * factor).rounded())
            append(latitude - lastLatitude)
            append(longitude - lastLongitude)
            lastLatitude = latitude
            lastLongitude = longitude
        }
        return encoded
    }
}
