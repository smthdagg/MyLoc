import Foundation
import Security

public protocol PairingStore: Sendable {
    func save(data: Data, summary: PairingSummary) throws
    func loadData() -> Data?
    func loadSummary() -> PairingSummary?
    func delete() throws
}

/// Stores pairing record exclusively in Keychain with `WhenUnlockedThisDeviceOnly` (FR-103).
public final class KeychainPairingStore: PairingStore, @unchecked Sendable {
    private let service: String
    private let dataAccount = "myloc.pairing.data"
    private let summaryAccount = "myloc.pairing.summary"

    public init(service: String = "com.myloc.app.keychain") {
        self.service = service
    }

    public func save(data: Data, summary: PairingSummary) throws {
        try saveItem(account: dataAccount, data: data)
        let summaryData = try JSONEncoder().encode(summary)
        try saveItem(account: summaryAccount, data: summaryData)
    }

    public func loadData() -> Data? {
        loadItem(account: dataAccount)
    }

    public func loadSummary() -> PairingSummary? {
        guard let data = loadItem(account: summaryAccount) else { return nil }
        return try? JSONDecoder().decode(PairingSummary.self, from: data)
    }

    public func delete() throws {
        deleteItem(account: dataAccount)
        deleteItem(account: summaryAccount)
    }

    private func saveItem(account: String, data: Data) throws {
        deleteItem(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func loadItem(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func deleteItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// In-memory pairing store for unit tests.
public final class InMemoryPairingStore: PairingStore, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var summary: PairingSummary?

    public init() {}

    public func save(data: Data, summary: PairingSummary) throws {
        lock.lock(); defer { lock.unlock() }
        self.data = data
        self.summary = summary
    }

    public func loadData() -> Data? {
        lock.lock(); defer { lock.unlock() }
        return data
    }

    public func loadSummary() -> PairingSummary? {
        lock.lock(); defer { lock.unlock() }
        return summary
    }

    public func delete() throws {
        lock.lock(); defer { lock.unlock() }
        data = nil
        summary = nil
    }
}

/// Persists preferences, favorites, history (max 30), and session recovery record in `UserDefaults` (FR-601~704).
public final class LocalDataStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let prefsKey = "myloc.preferences"
    private let favoritesKey = "myloc.favorites"
    private let historyKey = "myloc.history"
    private let sessionKey = "myloc.session_record"
    private let maxHistoryCount = 30
    private var lastSessionWriteDate: Date = .distantPast

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadPreferences() -> Preferences {
        guard let data = defaults.data(forKey: prefsKey),
              let prefs = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return Preferences()
        }
        return prefs
    }

    public func savePreferences(_ prefs: Preferences) {
        if let data = try? JSONEncoder().encode(prefs) {
            defaults.set(data, forKey: prefsKey)
        }
    }

    public func loadFavorites() -> [Place] {
        guard let data = defaults.data(forKey: favoritesKey),
              let list = try? JSONDecoder().decode([Place].self, from: data) else {
            return []
        }
        return list
    }

    public func saveFavorites(_ places: [Place]) {
        if let data = try? JSONEncoder().encode(places) {
            defaults.set(data, forKey: favoritesKey)
        }
    }

    public func loadHistory() -> [Place] {
        guard let data = defaults.data(forKey: historyKey),
              let list = try? JSONDecoder().decode([Place].self, from: data) else {
            return []
        }
        return list
    }

    public func recordHistory(_ place: Place) {
        var list = loadHistory()
        list.removeAll { $0.latitude == place.latitude && $0.longitude == place.longitude }
        list.insert(place, at: 0)
        if list.count > maxHistoryCount {
            list = Array(list.prefix(maxHistoryCount))
        }
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: historyKey)
        }
    }

    public func saveHistory(_ places: [Place]) {
        let trimmed = Array(places.prefix(maxHistoryCount))
        if let data = try? JSONEncoder().encode(trimmed) {
            defaults.set(data, forKey: historyKey)
        }
    }

    public func loadSessionRecord() -> SessionRecord? {
        guard let data = defaults.data(forKey: sessionKey),
              let record = try? JSONDecoder().decode(SessionRecord.self, from: data) else {
            return nil
        }
        return record
    }

    /// Throttled to at most once every 5 seconds unless `force == true` (FR-701).
    public func saveSessionRecord(_ record: SessionRecord, force: Bool = false, now: Date = Date()) {
        if !force && now.timeIntervalSince(lastSessionWriteDate) < 5.0 {
            return
        }
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: sessionKey)
            lastSessionWriteDate = now
        }
    }

    public func clearSessionRecord() {
        defaults.removeObject(forKey: sessionKey)
    }

    public func resetAll() {
        defaults.removeObject(forKey: prefsKey)
        defaults.removeObject(forKey: favoritesKey)
        defaults.removeObject(forKey: historyKey)
        defaults.removeObject(forKey: sessionKey)
    }
}
