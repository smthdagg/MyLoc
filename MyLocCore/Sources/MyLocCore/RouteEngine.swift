import Foundation

/// Pure-function route simulation engine (FR-501~508, T-302, T-305).
public struct RouteProgress: Equatable, Sendable {
    public var currentCoordinate: Coordinate
    public var traveledMeters: Double
    public var totalMeters: Double
    public var remainingSeconds: Double
    public var isFinished: Bool
    public var isReversed: Bool

    public var fractionCompleted: Double {
        guard totalMeters > 0 else { return 1.0 }
        return min(1.0, max(0.0, traveledMeters / totalMeters))
    }
}

public struct RouteEngine: Sendable {
    public private(set) var waypoints: [Coordinate]
    public private(set) var segmentLengths: [Double]
    public private(set) var totalMeters: Double
    public private(set) var traveledMeters: Double = 0
    public private(set) var isReversed: Bool = false

    public init?(waypoints: [Coordinate]) {
        let valid = waypoints.filter { $0.isValid }
        guard valid.count >= 2 else { return nil }
        self.waypoints = valid
        var lengths: [Double] = []
        var total = 0.0
        for i in 0..<(valid.count - 1) {
            let d = CoordinateConverter.distanceMeters(from: valid[i], to: valid[i + 1])
            lengths.append(d)
            total += d
        }
        self.segmentLengths = lengths
        self.totalMeters = total
    }

    /// Straight-line interpolation fallback when MapKit directions are unavailable (D3 / T-305).
    public static func straightLine(from start: Coordinate, to end: Coordinate, steps: Int = 20) -> RouteEngine? {
        guard start.isValid, end.isValid else { return nil }
        let n = max(2, steps)
        var pts: [Coordinate] = []
        for i in 0...n {
            let t = Double(i) / Double(n)
            pts.append(Coordinate(
                latitude: start.latitude + (end.latitude - start.latitude) * t,
                longitude: start.longitude + (end.longitude - start.longitude) * t
            ))
        }
        return RouteEngine(waypoints: pts)
    }

    public mutating func reverse() {
        isReversed.toggle()
        waypoints.reverse()
        segmentLengths.reverse()
        traveledMeters = max(0, totalMeters - traveledMeters)
    }

    public mutating func reset() {
        traveledMeters = 0
    }

    /// Advances along the route by `deltaSeconds` at `speedMetersPerSecond`.
    public mutating func advance(deltaSeconds: Double, speedMetersPerSecond: Double) -> RouteProgress {
        let speed = max(0.1, speedMetersPerSecond)
        if deltaSeconds > 0 {
            traveledMeters = min(totalMeters, traveledMeters + deltaSeconds * speed)
        }
        let coord = coordinate(atDistance: traveledMeters)
        let remainingMeters = max(0, totalMeters - traveledMeters)
        return RouteProgress(
            currentCoordinate: coord,
            traveledMeters: traveledMeters,
            totalMeters: totalMeters,
            remainingSeconds: remainingMeters / speed,
            isFinished: traveledMeters >= totalMeters - 1e-6,
            isReversed: isReversed
        )
    }

    public func coordinate(atDistance distance: Double) -> Coordinate {
        guard !waypoints.isEmpty else { return Coordinate(latitude: 0, longitude: 0) }
        if distance <= 0 { return waypoints[0] }
        if distance >= totalMeters { return waypoints[waypoints.count - 1] }

        var remaining = distance
        for i in 0..<segmentLengths.count {
            let seg = segmentLengths[i]
            if remaining <= seg || i == segmentLengths.count - 1 {
                let ratio = seg > 0 ? min(1.0, max(0.0, remaining / seg)) : 0
                let a = waypoints[i]
                let b = waypoints[i + 1]
                return Coordinate(
                    latitude: a.latitude + (b.latitude - a.latitude) * ratio,
                    longitude: a.longitude + (b.longitude - a.longitude) * ratio
                )
            }
            remaining -= seg
        }
        return waypoints[waypoints.count - 1]
    }
}

/// GPX 1.1 import/export with coordinate sanitization and multi-segment rejection (FR-508).
public enum GPXCodec {
    public enum GPXError: Error, Equatable, Sendable {
        case invalidXML
        case multipleSegmentsNotSupported
        case insufficientPoints
    }

    public static func exportGPX(name: String, waypoints: [Coordinate]) -> String {
        let safeName = name
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        var lines: [String] = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<gpx version=\"1.1\" creator=\"MyLoc\" xmlns=\"http://www.topografix.com/GPX/1/1\">",
            "  <trk>",
            "    <name>\(safeName)</name>",
            "    <trkseg>"
        ]
        for pt in waypoints where pt.isValid {
            lines.append(String(format: "      <trkpt lat=\"%.6f\" lon=\"%.6f\"></trkpt>", pt.latitude, pt.longitude))
        }
        lines.append("    </trkseg>")
        lines.append("  </trk>")
        lines.append("</gpx>")
        return lines.joined(separator: "\n")
    }

    public static func importGPX(data: Data) throws -> [Coordinate] {
        guard let xml = String(data: data, encoding: .utf8), xml.contains("<gpx") else {
            throw GPXError.invalidXML
        }
        let segCount = xml.components(separatedBy: "<trkseg").count - 1
        if segCount > 1 {
            throw GPXError.multipleSegmentsNotSupported
        }
        let pattern = #"<trkpt\s+[^>]*lat="([^"]+)"[^>]*lon="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            throw GPXError.invalidXML
        }
        let range = NSRange(xml.startIndex..., in: xml)
        var coords: [Coordinate] = []
        for match in regex.matches(in: xml, options: [], range: range) {
            if let latRange = Range(match.range(at: 1), in: xml),
               let lonRange = Range(match.range(at: 2), in: xml),
               let lat = Double(xml[latRange]),
               let lon = Double(xml[lonRange]) {
                let c = Coordinate(latitude: lat, longitude: lon)
                if c.isValid {
                    coords.append(c)
                }
            }
        }
        guard coords.count >= 2 else {
            throw GPXError.insufficientPoints
        }
        return coords
    }
}
