import Foundation
import MapKit
import Observation
import SwiftUI
import UIKit
import MyLocCore

@MainActor
@Observable
final class AppViewModel: NSObject, MKLocalSearchCompleterDelegate {
    // MARK: - Dependencies
    private let engine: any LocationEngine
    private let pairingStore: any PairingStore
    private let dataStore: LocalDataStore
    private let keepAlive = BackgroundKeepAlive()
    private let searchCompleter = MKLocalSearchCompleter()

    // MARK: - Tunnel constants
    let tunnelHost = "10.7.0.1"
    let tunnelPort: UInt16 = 49152

    // MARK: - Published State
    var preferences: Preferences
    var pairingSummary: PairingSummary?
    var sessionState: SessionState = .idle
    var lastFailure: FailureStage?
    var tunnelReachable: Bool = false
    var diagnosticEvents: [DiagnosticEvent] = []

    var selectedPlace: Place?
    var simulatedCoordinate: Coordinate?
    var realCoordinate: Coordinate?
    var followSimulatedLocation: Bool = true
    var statusBannerMessage: String?

    // Search
    var searchQuery: String = "" {
        didSet {
            searchCompleter.queryFragment = searchQuery
        }
    }
    var searchSuggestions: [MKLocalSearchCompletion] = []

    // Collections
    var favorites: [Place] = []
    var history: [Place] = []

    // Recovery (FR-701~704)
    var pendingRecoveryRecord: SessionRecord?
    var showRecoveryAlert: Bool = false

    // Legal Disclaimer (FR-311)
    var showDisclaimerSheet: Bool = false
    private var pendingActionAfterDisclaimer: (() async -> Void)?

    // Pending resume after returning from LocalDevVPN (FR-202)
    private var pendingStartAfterVPN: Bool = false

    // In-App Auto-Pairing (FR-105)
    enum AutoPairingState: Equatable {
        case idle
        case checkingTunnel
        case waitingForPin
        case verifyingPin
        case succeeded
        case failed(String)
    }
    var autoPairingState: AutoPairingState = .idle

    // Route Simulation (FR-501~509)
    var activeSessionKind: SessionKind = .fixed
    var routeWaypoints: [Coordinate] = []
    var routeProgress: RouteProgress?
    var isRoutePaused: Bool = false
    var selectedWalkPace: WalkPace = .normal
    var routeSpeedMultiplier: Double = 1.0
    private var routeEngine: RouteEngine?

    // Tasks
    private var heartbeatTask: Task<Void, Never>?
    private var routeTask: Task<Void, Never>?

    init(
        engine: (any LocationEngine)? = nil,
        pairingStore: any PairingStore = KeychainPairingStore(),
        dataStore: LocalDataStore = LocalDataStore()
    ) {
        #if targetEnvironment(simulator)
        self.engine = engine ?? MockLocationEngine(tunnelReachable: true)
        #else
        self.engine = engine ?? RustLocationEngine()
        #endif
        self.pairingStore = pairingStore
        self.dataStore = dataStore
        self.preferences = dataStore.loadPreferences()
        self.pairingSummary = pairingStore.loadSummary()
        self.favorites = dataStore.loadFavorites()
        self.history = dataStore.loadHistory()
        super.init()

        searchCompleter.delegate = self
        searchCompleter.region = MKCoordinateRegion(.world)
        searchCompleter.resultTypes = [.address, .pointOfInterest, .query]
        keepAlive.onRealLocationUpdate = { [weak self] coord in
            self?.realCoordinate = Coordinate(latitude: coord.latitude, longitude: coord.longitude)
        }
        keepAlive.requestPermissionIfNeeded()

        // Auto-import staged pairing file from Documents into Keychain, then delete staging file (FR-103)
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let staged = docs.appendingPathComponent("pairing.mobiledevicepairing")
            if FileManager.default.fileExists(atPath: staged.path) {
                importPairingFile(url: staged)
                try? FileManager.default.removeItem(at: staged)
            }
        }

        if let record = dataStore.loadSessionRecord() {
            self.pendingRecoveryRecord = record
            self.showRecoveryAlert = true
        }
    }

    var hasPairing: Bool {
        pairingStore.loadData() != nil
    }

    // MARK: - Pairing (FR-101~107)
    func importPairingFile(url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let summary = try PairingValidator.validateAndSummarize(data: data)
            try pairingStore.save(data: data, summary: summary)
            self.pairingSummary = summary
            self.lastFailure = nil
            recordEvent(stage: "pairing", code: "IMPORT_OK")
            statusBannerMessage = "配对记录导入成功，设备已就绪。"
        } catch {
            self.lastFailure = .pairingRecord
            recordEvent(stage: "pairing", code: FailureStage.pairingRecord.diagnosticCode)
            statusBannerMessage = FailureStage.pairingRecord.userMessageZh
        }
    }

    func deletePairing() {
        try? pairingStore.delete()
        pairingSummary = nil
        autoPairingState = .idle
        recordEvent(stage: "pairing", code: "DELETED")
        statusBannerMessage = "已删除配对记录。"
    }

    // MARK: - In-App Auto-Pairing (FR-105)
    func startAutoPairing() async {
        autoPairingState = .checkingTunnel
        let reachable = await checkTunnel()
        guard reachable else {
            autoPairingState = .failed("本地隧道未连通，请先打开 LocalDevVPN 连接后再发起配对。")
            return
        }
        recordEvent(stage: "pairing", code: "AUTO_PAIR_DISCOVER")
        let pairingPort = await BonjourDiscovery.discoverRemotePairingPort() ?? tunnelPort
        recordEvent(stage: "pairing", code: "AUTO_PAIR_PORT_\(pairingPort)")
        autoPairingState = .verifyingPin

        let res = await engine.pairDevice(host: tunnelHost, port: pairingPort, timeoutMs: 45000)
        switch res {
        case .success(let data):
            do {
                let summary = try PairingValidator.validateAndSummarize(data: data)
                try pairingStore.save(data: data, summary: summary)
                self.pairingSummary = summary
                self.lastFailure = nil
                self.autoPairingState = .succeeded
                recordEvent(stage: "pairing", code: "AUTO_PAIR_OK")
                statusBannerMessage = "自动配对成功，配对记录已存入 Keychain。"
            } catch {
                autoPairingState = .failed("配对数据校验失败，请重试。")
            }
        case .failure(let err):
            recordEvent(stage: "pairing", code: "AUTO_PAIR_FAIL")
            autoPairingState = .failed("配对失败（\(tunnelHost):\(pairingPort)）：\(err.message)")
        }
    }

    func submitPairingPin(_ pin: String) async {
        guard pin.count == 6, pin.allSatisfy(\.isNumber) else {
            autoPairingState = .failed("请输入完整的 6 位数字配对码。")
            return
        }
        autoPairingState = .verifyingPin
        let res = await engine.submitPairingPin(pin)
        switch res {
        case .success(let data):
            do {
                let summary = try PairingValidator.validateAndSummarize(data: data)
                try pairingStore.save(data: data, summary: summary)
                self.pairingSummary = summary
                self.lastFailure = nil
                self.autoPairingState = .succeeded
                recordEvent(stage: "pairing", code: "AUTO_PAIR_OK")
                statusBannerMessage = "自动配对成功，配对记录已安全存入 Keychain。"
            } catch {
                autoPairingState = .failed("配对数据校验失败，请重试或从文件导入。")
            }
        case .failure(let stage):
            recordEvent(stage: "pairing", code: stage.diagnosticCode)
            autoPairingState = .failed(stage.userMessageZh)
        }
    }

    // MARK: - Tunnel (FR-201~202)
    func checkTunnel() async -> Bool {
        let res = await engine.probeTunnel(host: tunnelHost, port: tunnelPort, timeoutMs: 3000)
        switch res {
        case .success:
            tunnelReachable = true
            recordEvent(stage: "tunnel", code: "REACHABLE")
            return true
        case .failure:
            tunnelReachable = false
            recordEvent(stage: "tunnel", code: FailureStage.tunnelUnreachable.diagnosticCode)
            return false
        }
    }

    func openLocalDevVPN() {
        pendingStartAfterVPN = true
        if let url = URL(string: "localdevvpn://") {
            UIApplication.shared.open(url)
        }
    }

    func handleAppDidBecomeActive() async {
        _ = await checkTunnel()
        if pendingStartAfterVPN && tunnelReachable {
            pendingStartAfterVPN = false
            await startFixedSession()
        }
    }

    // MARK: - Selection & Search (FR-301~303)
    func selectCoordinate(_ coord: Coordinate, name: String = "自选位置", subtitle: String = "") {
        guard coord.isValid else { return }
        let place = Place(name: name, subtitle: subtitle, latitude: coord.latitude, longitude: coord.longitude)
        selectedPlace = place
        if sessionState == .active && activeSessionKind == .fixed {
            Task { await updateActiveCoordinate(coord, place: place) }
        }
    }

    func selectCoordinateFromText(_ text: String) -> Bool {
        guard let coord = CoordinateConverter.parseCoordinateText(text) else {
            statusBannerMessage = "经纬度格式无效，请输入“纬度, 经度”（例如 39.9042, 116.4074）。"
            return false
        }
        selectCoordinate(coord, name: String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
        return true
    }

    /// Built-in global city presets so overseas search works even when Mainland China MapKit (AutoNavi) restricts results.
    static let globalPresets: [Place] = [
        Place(name: "香港 中环", subtitle: "Hong Kong", latitude: 22.2819, longitude: 114.1583),
        Place(name: "澳门 议事亭前地", subtitle: "Macau", latitude: 22.1937, longitude: 113.5398),
        Place(name: "台北 101", subtitle: "Taipei, Taiwan", latitude: 25.0339, longitude: 121.5645),
        Place(name: "东京 涩谷", subtitle: "Tokyo, Japan", latitude: 35.6595, longitude: 139.7004),
        Place(name: "新加坡 滨海湾", subtitle: "Singapore", latitude: 1.2834, longitude: 103.8607),
        Place(name: "伦敦 泰晤士河", subtitle: "London, UK", latitude: 51.5007, longitude: -0.1246),
        Place(name: "巴黎 埃菲尔铁塔", subtitle: "Paris, France", latitude: 48.8584, longitude: 2.2945),
        Place(name: "纽约 时代广场", subtitle: "New York, USA", latitude: 40.7580, longitude: -73.9855),
        Place(name: "旧金山 联合广场", subtitle: "San Francisco, USA", latitude: 37.7879, longitude: -122.4074),
        Place(name: "洛杉矶 好莱坞", subtitle: "Los Angeles, USA", latitude: 34.0928, longitude: -118.3287),
        Place(name: "悉尼 歌剧院", subtitle: "Sydney, Australia", latitude: -33.8568, longitude: 151.2153),
        Place(name: "首尔 明洞", subtitle: "Seoul, South Korea", latitude: 37.5636, longitude: 126.9826),
        Place(name: "柏林 勃兰登堡门", subtitle: "Berlin, Germany", latitude: 52.5163, longitude: 13.3777),
        Place(name: "多伦多 CN 塔", subtitle: "Toronto, Canada", latitude: 43.6426, longitude: -79.3871),
    ]

    func cycleMapStyle() {
        switch preferences.mapStyle {
        case .standard:  preferences.mapStyle = .satellite
        case .satellite: preferences.mapStyle = .hybrid
        case .hybrid:    preferences.mapStyle = .standard
        }
        savePreferences()
    }

    /// Global search submit: supports coordinates, built-in global cities, worldwide MKLocalSearch, and CLGeocoder fallback.
    func performSearchSubmit() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        if let coord = CoordinateConverter.parseCoordinateText(query) {
            searchQuery = ""
            searchSuggestions = []
            selectCoordinate(coord, name: String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
            return
        }

        // 0. Instant match against global presets (bypasses Mainland China AutoNavi overseas restriction)
        let lower = query.lowercased()
        if let preset = Self.globalPresets.first(where: {
            $0.name.lowercased().contains(lower) || $0.subtitle.lowercased().contains(lower)
        }) {
            searchQuery = ""
            searchSuggestions = []
            selectCoordinate(preset.coordinate, name: preset.name, subtitle: preset.subtitle)
            return
        }

        // 1. Worldwide MKLocalSearch
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(.world)
        if let response = try? await MKLocalSearch(request: request).start(),
           let item = response.mapItems.first {
            let loc = item.location.coordinate
            searchQuery = ""
            searchSuggestions = []
            selectCoordinate(
                Coordinate(latitude: loc.latitude, longitude: loc.longitude),
                name: item.name ?? query,
                subtitle: ""
            )
            return
        }

        // 2. Fallback to CLGeocoder for international countries / cities
        let geocoder = CLGeocoder()
        if let placemarks = try? await geocoder.geocodeAddressString(query),
           let first = placemarks.first,
           let loc = first.location?.coordinate {
            let title = [first.name, first.locality, first.country]
                .compactMap { $0 }
                .joined(separator: ", ")
            searchQuery = ""
            searchSuggestions = []
            selectCoordinate(
                Coordinate(latitude: loc.latitude, longitude: loc.longitude),
                name: title.isEmpty ? query : title,
                subtitle: first.country ?? ""
            )
            return
        }

        statusBannerMessage = "未找到“\(query)”，可点击上方快捷城市或直接输入“纬度, 经度”。"
    }

    func selectSearchCompletion(_ completion: MKLocalSearchCompletion) async {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start(),
              let item = response.mapItems.first else { return }
        let loc = item.location.coordinate
        let coord = Coordinate(latitude: loc.latitude, longitude: loc.longitude)
        searchQuery = ""
        searchSuggestions = []
        selectCoordinate(coord, name: completion.title, subtitle: completion.subtitle)
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            self.searchSuggestions = self.searchCompleter.results
        }
    }

    // MARK: - Fixed Location Session (FR-304~308)
    func requestStartFixedSession() {
        guard preferences.hasAcceptedDisclaimer else {
            pendingActionAfterDisclaimer = { [weak self] in
                await self?.startFixedSession()
            }
            showDisclaimerSheet = true
            return
        }
        Task { await startFixedSession() }
    }

    func acceptDisclaimerAndContinue() {
        preferences.hasAcceptedDisclaimer = true
        dataStore.savePreferences(preferences)
        showDisclaimerSheet = false
        let action = pendingActionAfterDisclaimer
        pendingActionAfterDisclaimer = nil
        if let action {
            Task { await action() }
        }
    }

    func startFixedSession() async {
        guard let target = selectedPlace else {
            statusBannerMessage = "请先在地图上点选或搜索目标位置。"
            return
        }
        activeSessionKind = .fixed
        guard await ensureConnected() else { return }
        await updateActiveCoordinate(target.coordinate, place: target)
        startHeartbeatLoop()
    }

    private func ensureConnected() async -> Bool {
        if sessionState == .active { return true }
        sessionState = .preparing
        guard let pairingData = pairingStore.loadData() else {
            fail(.pairingRecord)
            return false
        }

        sessionState = .tunnel
        let reachable = await checkTunnel()
        guard reachable else {
            fail(.tunnelUnreachable)
            return false
        }

        sessionState = .discovering
        recordEvent(stage: "connect", code: "START")
        sessionState = .connecting
        let connRes = await engine.connect(
            host: tunnelHost,
            port: tunnelPort,
            pairingData: pairingData,
            timeoutMs: 12000
        )
        switch connRes {
        case .success:
            sessionState = .active
            lastFailure = nil
            recordEvent(stage: "connect", code: "ACTIVE")
            if preferences.backgroundKeepAliveEnabled {
                keepAlive.start(enableAudioSession: true)
            }
            return true
        case .failure(let stage):
            let detail = await engine.lastErrorMessage()
            fail(stage, detail: detail)
            return false
        }
    }

    private func deviceCoordinate(for wgs84: Coordinate) -> Coordinate {
        // Region-aware conversion (§9.1): only convert in Mainland China if enabled.
        if preferences.autoAdjustMainlandChinaGCJ02 {
            return CoordinateConverter.gcj02ToWgs84(wgs84)
        }
        return wgs84
    }

    private func updateActiveCoordinate(_ coord: Coordinate, place: Place?) async {
        let sendCoord = deviceCoordinate(for: coord)
        let res = await engine.setLocation(latitude: sendCoord.latitude, longitude: sendCoord.longitude)
        switch res {
        case .success:
            simulatedCoordinate = coord
            if let place {
                if activeSessionKind != .joystick {
                    dataStore.recordHistory(place)
                    history = dataStore.loadHistory()
                }
                let rec = SessionRecord(
                    kind: activeSessionKind,
                    lastPlace: place,
                    destination: nil,
                    pace: activeSessionKind == .walk ? selectedWalkPace : nil
                )
                dataStore.saveSessionRecord(rec, force: false)
            }
        case .failure(let stage):
            fail(stage)
        }
    }

    private func startHeartbeatLoop() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard let self, self.sessionState == .active, let coord = self.simulatedCoordinate else {
                    break
                }
                if self.activeSessionKind == .fixed {
                    let sendCoord = self.deviceCoordinate(for: coord)
                    let res = await self.engine.setLocation(latitude: sendCoord.latitude, longitude: sendCoord.longitude)
                    if case .failure(let stage) = res {
                        self.fail(stage)
                        break
                    }
                }
            }
        }
    }

    func stopAndRestore() async {
        heartbeatTask?.cancel()
        routeTask?.cancel()
        sessionState = .stopping
        let res = await engine.clearLocation()
        await engine.disconnect()
        keepAlive.stop()
        simulatedCoordinate = nil
        routeEngine = nil
        routeProgress = nil
        dataStore.clearSessionRecord()

        switch res {
        case .success:
            sessionState = .idle
            recordEvent(stage: "restore", code: "OK")
            statusBannerMessage = "已停止位置模拟，系统正在重新获取真实位置。"
        case .failure(let stage):
            fail(stage)
        }
    }

    // MARK: - Route Simulation (FR-501~509)
    func startRoute(to destination: Place, kind: SessionKind, pace: WalkPace = .normal) async {
        let startCoord = simulatedCoordinate ?? realCoordinate ?? selectedPlace?.coordinate
        guard let origin = startCoord else {
            statusBannerMessage = "请先在地图上选择一个起点。"
            return
        }
        activeSessionKind = kind
        selectedWalkPace = pace
        isRoutePaused = false

        // Try Apple Maps directions first, fallback to straight-line interpolation (D3 / T-305)
        var waypoints: [Coordinate] = []
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: origin.latitude, longitude: origin.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil)
        request.transportType = (kind == .drive) ? .automobile : .walking

        if let response = try? await MKDirections(request: request).calculate(),
           let route = response.routes.first {
            let count = route.polyline.pointCount
            var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: count)
            route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
            waypoints = coords.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
        }

        if waypoints.count >= 2, let engine = RouteEngine(waypoints: waypoints) {
            self.routeEngine = engine
            self.routeWaypoints = engine.waypoints
        } else if let fallback = RouteEngine.straightLine(from: origin, to: destination.coordinate) {
            self.routeEngine = fallback
            self.routeWaypoints = fallback.waypoints
            statusBannerMessage = "无法获取地图路线，已自动切换为直线插值路线。"
        } else {
            statusBannerMessage = "无法规划路线，请检查起终点。"
            return
        }

        guard await ensureConnected() else { return }
        runRouteLoop(destination: destination)
    }

    func startGPXRoute(data: Data) async {
        do {
            let pts = try GPXCodec.importGPX(data: data)
            guard let engine = RouteEngine(waypoints: pts) else { return }
            self.routeEngine = engine
            self.routeWaypoints = engine.waypoints
            self.activeSessionKind = .walk
            self.isRoutePaused = false
            guard await ensureConnected() else { return }
            let dest = Place(name: "GPX 终点", latitude: pts.last!.latitude, longitude: pts.last!.longitude)
            runRouteLoop(destination: dest)
        } catch {
            statusBannerMessage = "GPX 导入失败：仅支持单段有效 GPX 1.1 文件。"
        }
    }

    private func runRouteLoop(destination: Place) {
        routeTask?.cancel()
        routeTask = Task { [weak self] in
            let tickSeconds = 1.0
            while !Task.isCancelled {
                guard let self, self.sessionState == .active else { break }
                if !self.isRoutePaused, var engine = self.routeEngine {
                    let baseSpeed: Double
                    switch self.activeSessionKind {
                    case .walk:  baseSpeed = self.selectedWalkPace.metersPerSecond
                    case .ride:  baseSpeed = 5.5
                    case .drive: baseSpeed = 13.8
                    default:     baseSpeed = 1.4
                    }
                    let progress = engine.advance(deltaSeconds: tickSeconds, speedMetersPerSecond: baseSpeed * self.routeSpeedMultiplier)
                    self.routeEngine = engine
                    self.routeProgress = progress
                    let place = Place(name: "路线模拟中", latitude: progress.currentCoordinate.latitude, longitude: progress.currentCoordinate.longitude)
                    await self.updateActiveCoordinate(progress.currentCoordinate, place: place)
                    if progress.isFinished {
                        self.statusBannerMessage = "已到达终点：\(destination.name)"
                        break
                    }
                }
                try? await Task.sleep(for: .seconds(tickSeconds))
            }
        }
    }

    func toggleRoutePause() {
        isRoutePaused.toggle()
    }

    func reverseRoute() {
        routeEngine?.reverse()
        if let engine = routeEngine {
            routeWaypoints = engine.waypoints
        }
    }

    /// Virtual joystick nudge (FR-509, does not write to history).
    func nudgeJoystick(dLat: Double, dLon: Double) async {
        let base = simulatedCoordinate ?? selectedPlace?.coordinate ?? Coordinate(latitude: 39.9042, longitude: 116.4074)
        let next = Coordinate(latitude: base.latitude + dLat, longitude: base.longitude + dLon)
        guard next.isValid else { return }
        activeSessionKind = .joystick
        guard await ensureConnected() else { return }
        await updateActiveCoordinate(next, place: nil)
    }

    // MARK: - Favorites & History (FR-601~603)
    func addFavorite(_ place: Place) {
        guard !favorites.contains(where: { $0.id == place.id }) else { return }
        favorites.insert(place, at: 0)
        dataStore.saveFavorites(favorites)
    }

    func deleteFavorites(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        dataStore.saveFavorites(favorites)
    }

    func moveFavorites(from source: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        dataStore.saveFavorites(favorites)
    }

    func renameFavorite(id: UUID, newName: String) {
        guard let idx = favorites.firstIndex(where: { $0.id == id }) else { return }
        favorites[idx].name = newName
        dataStore.saveFavorites(favorites)
    }

    func clearHistory() {
        history = []
        dataStore.saveHistory([])
    }

    // MARK: - Session Recovery (FR-701~704)
    func recoverLastSession() async {
        guard let rec = pendingRecoveryRecord else { return }
        showRecoveryAlert = false
        pendingRecoveryRecord = nil
        selectedPlace = rec.lastPlace
        if rec.kind == .walk, let dest = rec.destination {
            await startRoute(to: dest, kind: .walk, pace: rec.pace ?? .normal)
        } else {
            await startFixedSession()
        }
    }

    func recoverRestoreRealLocation() async {
        showRecoveryAlert = false
        pendingRecoveryRecord = nil
        dataStore.clearSessionRecord()
        if await ensureConnected() {
            await stopAndRestore()
        }
    }

    func ignoreRecovery() {
        showRecoveryAlert = false
        pendingRecoveryRecord = nil
        dataStore.clearSessionRecord()
    }

    // MARK: - Settings, Diagnostics & Reset (FR-801~806)
    func savePreferences() {
        dataStore.savePreferences(preferences)
    }

    func completeOnboarding() {
        preferences.hasOnboarded = true
        dataStore.savePreferences(preferences)
    }

    func buildDiagnosticsText() -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let osVersion = UIDevice.current.systemVersion
        return DiagnosticsBuilder.build(
            appVersion: appVersion,
            osVersion: osVersion,
            hasPairing: hasPairing,
            tunnelReachable: tunnelReachable,
            sessionState: sessionState,
            lastFailure: lastFailure,
            events: diagnosticEvents
        )
    }

    func resetApp() async {
        if sessionState == .active {
            await stopAndRestore()
        }
        try? pairingStore.delete()
        dataStore.resetAll()
        pairingSummary = nil
        favorites = []
        history = []
        selectedPlace = nil
        simulatedCoordinate = nil
        lastFailure = nil
        diagnosticEvents = []
        preferences = Preferences()
        sessionState = .idle
    }

    // MARK: - Helpers
    private func fail(_ stage: FailureStage, detail: String = "") {
        sessionState = .failed(stage)
        lastFailure = stage
        statusBannerMessage = detail.isEmpty ? stage.userMessageZh : "\(stage.userMessageZh)\n[\(detail)]"
        recordEvent(stage: "error", code: detail.isEmpty ? stage.diagnosticCode : "\(stage.diagnosticCode): \(detail)")
    }

    private func recordEvent(stage: String, code: String) {
        diagnosticEvents.append(DiagnosticEvent(stage: stage, code: code))
        if diagnosticEvents.count > 50 {
            diagnosticEvents.removeFirst(diagnosticEvents.count - 50)
        }
    }
}
