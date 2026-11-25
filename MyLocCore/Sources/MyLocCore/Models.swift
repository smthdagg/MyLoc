import Foundation

public struct Coordinate: Codable, Equatable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite &&
        (-90.0...90.0).contains(latitude) &&
        (-180.0...180.0).contains(longitude)
    }
}

public struct Place: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var subtitle: String
    public var latitude: Double
    public var longitude: Double

    public init(
        id: UUID = UUID(),
        name: String,
        subtitle: String = "",
        latitude: Double,
        longitude: Double
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
    }

    public var coordinate: Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }
}

public enum SessionKind: String, Codable, CaseIterable, Sendable {
    case fixed
    case walk
    case drive
    case ride
    case joystick
}

public enum WalkPace: String, Codable, CaseIterable, Sendable {
    case stroll   // ~1.1 m/s (~4 km/h)
    case normal   // ~1.4 m/s (~5 km/h)
    case brisk    // ~1.8 m/s (~6.5 km/h)
    case jog      // ~2.8 m/s (~10 km/h)

    public var metersPerSecond: Double {
        switch self {
        case .stroll: return 1.1
        case .normal: return 1.4
        case .brisk:  return 1.8
        case .jog:    return 2.8
        }
    }

    public var displayNameZh: String {
        switch self {
        case .stroll: return "散步 (4 km/h)"
        case .normal: return "正常步行 (5 km/h)"
        case .brisk:  return "快走 (6.5 km/h)"
        case .jog:    return "慢跑 (10 km/h)"
        }
    }
}

public struct SessionRecord: Codable, Equatable, Sendable {
    public var kind: SessionKind
    public var lastPlace: Place
    public var destination: Place?
    public var pace: WalkPace?
    public var updatedAt: Date

    public init(
        kind: SessionKind,
        lastPlace: Place,
        destination: Place? = nil,
        pace: WalkPace? = nil,
        updatedAt: Date = Date()
    ) {
        self.kind = kind
        self.lastPlace = lastPlace
        self.destination = destination
        self.pace = pace
        self.updatedAt = updatedAt
    }
}

public enum AppAppearance: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark
}

public enum MapStyleOption: String, Codable, CaseIterable, Sendable {
    case standard
    case satellite
    case hybrid
}

public enum DistanceUnit: String, Codable, CaseIterable, Sendable {
    case system
    case metric
    case imperial

    public func resolvedIsMetric(locale: Locale = .current) -> Bool {
        switch self {
        case .metric: return true
        case .imperial: return false
        case .system: return locale.measurementSystem == .metric
        }
    }

    public func formatDistance(meters: Double, locale: Locale = .current) -> String {
        if resolvedIsMetric(locale: locale) {
            if meters < 1000 {
                return String(format: "%.0f m", meters)
            }
            return String(format: "%.2f km", meters / 1000.0)
        } else {
            let feet = meters * 3.28084
            if feet < 1000 {
                return String(format: "%.0f ft", feet)
            }
            let miles = meters / 1609.344
            return String(format: "%.2f mi", miles)
        }
    }

    public func formatSpeed(metersPerSecond: Double, locale: Locale = .current) -> String {
        if resolvedIsMetric(locale: locale) {
            return String(format: "%.1f km/h", metersPerSecond * 3.6)
        } else {
            return String(format: "%.1f mph", metersPerSecond * 2.236936)
        }
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var appearance: AppAppearance
    public var mapStyle: MapStyleOption
    public var units: DistanceUnit
    public var language: String // "system", "zh-Hans", "en"
    public var hasOnboarded: Bool
    public var hasAcceptedDisclaimer: Bool
    public var autoAdjustMainlandChinaGCJ02: Bool
    public var backgroundKeepAliveEnabled: Bool

    public init(
        appearance: AppAppearance = .system,
        mapStyle: MapStyleOption = .standard,
        units: DistanceUnit = .system,
        language: String = "system",
        hasOnboarded: Bool = false,
        hasAcceptedDisclaimer: Bool = false,
        autoAdjustMainlandChinaGCJ02: Bool = true,
        backgroundKeepAliveEnabled: Bool = true
    ) {
        self.appearance = appearance
        self.mapStyle = mapStyle
        self.units = units
        self.language = language
        self.hasOnboarded = hasOnboarded
        self.hasAcceptedDisclaimer = hasAcceptedDisclaimer
        self.autoAdjustMainlandChinaGCJ02 = autoAdjustMainlandChinaGCJ02
        self.backgroundKeepAliveEnabled = backgroundKeepAliveEnabled
    }
}

public struct PairingSummary: Codable, Equatable, Sendable {
    public var deviceName: String
    public var model: String
    public var fingerprint: String
    public var importedAt: Date

    public init(
        deviceName: String,
        model: String,
        fingerprint: String,
        importedAt: Date = Date()
    ) {
        self.deviceName = deviceName
        self.model = model
        self.fingerprint = fingerprint
        self.importedAt = importedAt
    }
}
