import Foundation

/// Region-aware WGS-84 <-> GCJ-02 coordinate converter (Requirements §9.1, NFR-110).
///
/// - Only applies GCJ-02 offset inside Mainland China (excluding Hong Kong, Macau, Taiwan).
/// - All other regions (HK, Macau, Taiwan, Europe, Americas, etc.) pass through unchanged.
/// - Round-trip accuracy is < 1 meter via iterative inverse refinement.
public enum CoordinateConverter {
    private static let a: Double = 6378245.0
    private static let ee: Double = 0.00669342162296594323

    /// Parses `"lat, lon"` text input with range validation (FR-303).
    public static func parseCoordinateText(_ text: String) -> Coordinate? {
        let normalized = text
            .replacingOccurrences(of: "，", with: ",")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = normalized.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]) else {
            return nil
        }
        let coord = Coordinate(latitude: lat, longitude: lon)
        return coord.isValid ? coord : nil
    }

    /// Returns true if coordinate falls within Mainland China (excluding HK, Macau, Taiwan).
    public static func isInMainlandChina(_ coord: Coordinate) -> Bool {
        let lat = coord.latitude
        let lon = coord.longitude

        // Coarse bounding box for China
        guard lon >= 72.004 && lon <= 137.8347 && lat >= 0.8293 && lat <= 55.8271 else {
            return false
        }

        // Exclude Taiwan (coarse box)
        if lat >= 21.8 && lat <= 25.4 && lon >= 119.3 && lon <= 122.2 {
            return false
        }

        // Exclude Hong Kong (coarse box)
        if lat >= 22.13 && lat <= 22.50 && lon >= 113.82 && lon <= 114.44 {
            return false
        }

        // Exclude Macau (coarse box)
        if lat >= 22.10 && lat <= 22.22 && lon >= 113.52 && lon <= 113.60 {
            return false
        }

        return true
    }

    /// Converts WGS-84 to GCJ-02 if in Mainland China; otherwise returns input unchanged.
    public static func wgs84ToGcj02(_ coord: Coordinate) -> Coordinate {
        guard coord.isValid, isInMainlandChina(coord) else { return coord }
        let (dLat, dLon) = delta(lat: coord.latitude, lon: coord.longitude)
        return Coordinate(latitude: coord.latitude + dLat, longitude: coord.longitude + dLon)
    }

    /// Converts GCJ-02 to WGS-84 if in Mainland China; otherwise returns input unchanged.
    /// Uses iterative fixed-point refinement to achieve < 0.01 m round-trip error.
    public static func gcj02ToWgs84(_ coord: Coordinate) -> Coordinate {
        guard coord.isValid, isInMainlandChina(coord) else { return coord }
        var wgs = coord
        for _ in 0..<6 {
            let gcj = wgs84ToGcj02(wgs)
            let dLat = gcj.latitude - coord.latitude
            let dLon = gcj.longitude - coord.longitude
            wgs.latitude -= dLat
            wgs.longitude -= dLon
            if abs(dLat) < 1e-10 && abs(dLon) < 1e-10 {
                break
            }
        }
        return wgs
    }

    /// Haversine distance in meters between two WGS-84 coordinates.
    public static func distanceMeters(from a: Coordinate, to b: Coordinate) -> Double {
        let r = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180.0
        let dLon = (b.longitude - a.longitude) * .pi / 180.0
        let lat1 = a.latitude * .pi / 180.0
        let lat2 = b.latitude * .pi / 180.0
        let h = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2.0 * r * atan2(sqrt(h), sqrt(max(0.0, 1.0 - h)))
    }

    private static func delta(lat: Double, lon: Double) -> (Double, Double) {
        let x = lon - 105.0
        let y = lat - 35.0
        var dLat = transformLat(x: x, y: y)
        var dLon = transformLon(x: x, y: y)
        let radLat = lat / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1.0 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        dLat = (dLat * 180.0) / ((a * (1.0 - ee)) / (magic * sqrtMagic) * .pi)
        dLon = (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)
        return (dLat, dLon)
    }

    private static func transformLat(x: Double, y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * .pi) + 320.0 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLon(x: Double, y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return ret
    }
}
