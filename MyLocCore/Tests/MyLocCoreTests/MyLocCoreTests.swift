import Foundation
import Testing
@testable import MyLocCore

@Suite("MyLocCore Unit Tests")
struct MyLocCoreTests {

    @Test("CoordinateConverter: Mainland China round-trip < 1m and non-Mainland passthrough")
    func testCoordinateConversion() {
        let mainlandPoints: [Coordinate] = [
            Coordinate(latitude: 39.9042, longitude: 116.4074), // Beijing
            Coordinate(latitude: 31.2304, longitude: 121.4737), // Shanghai
            Coordinate(latitude: 22.5431, longitude: 114.0579), // Shenzhen
        ]
        for wgs in mainlandPoints {
            #expect(CoordinateConverter.isInMainlandChina(wgs))
            let gcj = CoordinateConverter.wgs84ToGcj02(wgs)
            let offset = CoordinateConverter.distanceMeters(from: wgs, to: gcj)
            #expect(offset > 50.0)
            let back = CoordinateConverter.gcj02ToWgs84(gcj)
            let err = CoordinateConverter.distanceMeters(from: wgs, to: back)
            #expect(err < 1.0)
        }

        let outsidePoints: [Coordinate] = [
            Coordinate(latitude: 22.3193, longitude: 114.1694), // Hong Kong
            Coordinate(latitude: 22.1987, longitude: 113.5439), // Macau
            Coordinate(latitude: 25.0330, longitude: 121.5654), // Taipei
            Coordinate(latitude: 51.5074, longitude: -0.1278),  // London
            Coordinate(latitude: 40.7128, longitude: -74.0060), // New York
        ]
        for pt in outsidePoints {
            #expect(!CoordinateConverter.isInMainlandChina(pt))
            #expect(CoordinateConverter.wgs84ToGcj02(pt) == pt)
            #expect(CoordinateConverter.gcj02ToWgs84(pt) == pt)
        }
    }

    @Test("CoordinateConverter: Text parsing and range validation")
    func testParseCoordinateText() {
        #expect(CoordinateConverter.parseCoordinateText("39.9042, 116.4074") == Coordinate(latitude: 39.9042, longitude: 116.4074))
        #expect(CoordinateConverter.parseCoordinateText("22.3193，114.1694") == Coordinate(latitude: 22.3193, longitude: 114.1694))
        #expect(CoordinateConverter.parseCoordinateText("95.0, 10.0") == nil)
        #expect(CoordinateConverter.parseCoordinateText("10.0, 181.0") == nil)
        #expect(CoordinateConverter.parseCoordinateText("invalid") == nil)
    }

    @Test("RouteEngine: Straight-line fallback, advancement, and reverse")
    func testRouteEngine() {
        let start = Coordinate(latitude: 39.9000, longitude: 116.4000)
        let end = Coordinate(latitude: 39.9090, longitude: 116.4000) // ~1 km north
        var engine = RouteEngine.straightLine(from: start, to: end, steps: 10)!
        #expect(engine.totalMeters > 950 && engine.totalMeters < 1050)

        let p1 = engine.advance(deltaSeconds: 100, speedMetersPerSecond: 1.4)
        #expect(abs(p1.traveledMeters - 140.0) < 0.01)
        #expect(!p1.isFinished)

        engine.reverse()
        #expect(engine.isReversed)
        let p2 = engine.advance(deltaSeconds: 1000, speedMetersPerSecond: 2.0)
        #expect(p2.isFinished)
    }

    @Test("GPXCodec: Export/Import and multi-segment rejection")
    func testGPXCodec() throws {
        let pts = [
            Coordinate(latitude: 39.90, longitude: 116.40),
            Coordinate(latitude: 39.91, longitude: 116.41),
        ]
        let xml = GPXCodec.exportGPX(name: "Test Route", waypoints: pts)
        let imported = try GPXCodec.importGPX(data: Data(xml.utf8))
        #expect(imported.count == 2)

        let multiSeg = "<gpx><trk><trkseg><trkpt lat=\"1\" lon=\"1\"/></trkseg><trkseg><trkpt lat=\"2\" lon=\"2\"/></trkseg></trk></gpx>"
        #expect(throws: GPXCodec.GPXError.multipleSegmentsNotSupported) {
            _ = try GPXCodec.importGPX(data: Data(multiSeg.utf8))
        }
    }

    @Test("PairingValidator: Valid plist vs corrupt/empty")
    func testPairingValidator() throws {
        let validDict: [String: Any] = [
            "HostID": "12345678-1234-1234-1234-1234567890AB",
            "SystemBUID": "ABCDEF",
            "DeviceName": "Test iPhone",
            "ProductType": "iPhone18,2"
        ]
        let validData = try PropertyListSerialization.data(fromPropertyList: validDict, format: .xml, options: 0)
        let summary = try PairingValidator.validateAndSummarize(data: validData)
        #expect(summary.deviceName == "Test iPhone")
        #expect(summary.model == "iPhone18,2")
        #expect(!summary.fingerprint.isEmpty)

        #expect(throws: PairingValidator.ValidationError.emptyData) {
            _ = try PairingValidator.validateAndSummarize(data: Data())
        }
        #expect(throws: PairingValidator.ValidationError.invalidPlist) {
            _ = try PairingValidator.validateAndSummarize(data: Data("not plist".utf8))
        }
    }

    @Test("DiagnosticsBuilder: Strictly sanitized output (AC-10)")
    func testDiagnosticsSanitization() {
        let text = DiagnosticsBuilder.build(
            appVersion: "1.0.0",
            osVersion: "26.0",
            hasPairing: true,
            tunnelReachable: false,
            sessionState: .failed(.tunnelUnreachable),
            lastFailure: .tunnelUnreachable,
            events: [DiagnosticEvent(stage: "tunnel", code: "ERR_TUNNEL_UNREACHABLE")]
        )
        #expect(text.contains("ERR_TUNNEL_UNREACHABLE"))
        #expect(!text.contains("39.9042"))
        #expect(!text.contains("HostPrivateKey"))
        #expect(!text.contains("Test iPhone"))
    }

    @Test("LocalDataStore: History cap 30 and session throttle 5s")
    func testLocalDataStore() {
        let suite = "myloc.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = LocalDataStore(defaults: defaults)
        for i in 0..<35 {
            store.recordHistory(Place(name: "P\(i)", latitude: Double(i), longitude: Double(i)))
        }
        #expect(store.loadHistory().count == 30)

        let t0 = Date()
        let rec1 = SessionRecord(kind: .fixed, lastPlace: Place(name: "A", latitude: 1, longitude: 1))
        let rec2 = SessionRecord(kind: .fixed, lastPlace: Place(name: "B", latitude: 2, longitude: 2))
        store.saveSessionRecord(rec1, force: false, now: t0)
        store.saveSessionRecord(rec2, force: false, now: t0.addingTimeInterval(2)) // throttled
        #expect(store.loadSessionRecord()?.lastPlace.name == "A")
        store.saveSessionRecord(rec2, force: false, now: t0.addingTimeInterval(6)) // allowed
        #expect(store.loadSessionRecord()?.lastPlace.name == "B")

        store.resetAll()
        #expect(store.loadHistory().isEmpty)
        #expect(store.loadSessionRecord() == nil)
    }

    @Test("MockLocationEngine: Connect, write without reconnect, clear")
    func testMockEngine() async {
        let engine = MockLocationEngine(tunnelReachable: true)
        let probe = await engine.probeTunnel(host: "10.7.0.1", port: 49152, timeoutMs: 3000)
        #expect((try? probe.get()) != nil)

        let conn = await engine.connect(host: "10.7.0.1", port: 49152, pairingData: Data([1, 2, 3]), timeoutMs: 4000)
        #expect((try? conn.get()) != nil)

        _ = await engine.setLocation(latitude: 39.9, longitude: 116.4)
        _ = await engine.setLocation(latitude: 39.91, longitude: 116.41)
        #expect(await engine.connectCount == 1)
        #expect(await engine.writtenCoordinates.count == 2)

        let clr = await engine.clearLocation()
        #expect((try? clr.get()) != nil)
        #expect(await engine.clearCount == 1)
    }
}
