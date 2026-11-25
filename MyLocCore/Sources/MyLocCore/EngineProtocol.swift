import Foundation

public struct PairingMessageError: Error, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

/// Abstraction over the Rust `idevice` engine so Domain/UI can run with `MockLocationEngine`
/// in unit tests and the iOS Simulator (Plan §1, §8).
public protocol LocationEngine: Sendable {
    func probeTunnel(host: String, port: UInt16, timeoutMs: UInt32) async -> Result<Void, FailureStage>
    func connect(host: String, port: UInt16, pairingData: Data, timeoutMs: UInt32) async -> Result<Void, FailureStage>
    func setLocation(latitude: Double, longitude: Double) async -> Result<Void, FailureStage>
    func clearLocation() async -> Result<Void, FailureStage>
    func disconnect() async
    func startPairing(host: String, port: UInt16, timeoutMs: UInt32) async -> Result<Void, FailureStage>
    func submitPairingPin(_ pin: String) async -> Result<Data, FailureStage>
    func pairDevice(host: String, port: UInt16, timeoutMs: UInt32) async -> Result<Data, PairingMessageError>
    func lastErrorMessage() async -> String
}

/// Deterministic mock engine for Simulator & unit tests.
public actor MockLocationEngine: LocationEngine {
    public var tunnelReachable: Bool = true
    public var connectFailure: FailureStage? = nil
    public var writeFailure: FailureStage? = nil
    public var clearFailure: FailureStage? = nil

    public private(set) var isConnected: Bool = false
    public private(set) var connectCount: Int = 0
    public private(set) var writtenCoordinates: [Coordinate] = []
    public private(set) var clearCount: Int = 0

    public init(tunnelReachable: Bool = true) {
        self.tunnelReachable = tunnelReachable
    }

    public func probeTunnel(host: String, port: UInt16, timeoutMs: UInt32) async -> Result<Void, FailureStage> {
        tunnelReachable ? .success(()) : .failure(.tunnelUnreachable)
    }

    public func connect(host: String, port: UInt16, pairingData: Data, timeoutMs: UInt32) async -> Result<Void, FailureStage> {
        if let fail = connectFailure {
            return .failure(fail)
        }
        guard !pairingData.isEmpty else {
            return .failure(.pairingRecord)
        }
        isConnected = true
        connectCount += 1
        return .success(())
    }

    public func setLocation(latitude: Double, longitude: Double) async -> Result<Void, FailureStage> {
        guard isConnected else { return .failure(.activeWrite) }
        if let fail = writeFailure {
            return .failure(fail)
        }
        writtenCoordinates.append(Coordinate(latitude: latitude, longitude: longitude))
        return .success(())
    }

    public func clearLocation() async -> Result<Void, FailureStage> {
        if let fail = clearFailure {
            return .failure(fail)
        }
        clearCount += 1
        return .success(())
    }

    public func disconnect() async {
        isConnected = false
    }

    public func startPairing(host: String, port: UInt16, timeoutMs: UInt32) async -> Result<Void, FailureStage> {
        tunnelReachable ? .success(()) : .failure(.tunnelUnreachable)
    }

    public func submitPairingPin(_ pin: String) async -> Result<Data, FailureStage> {
        guard pin.count == 6 else { return .failure(.pairVerifyRejected) }
        let dict: [String: Any] = ["HostID": "MOCK-HOST", "DeviceName": "Simulator", "ProductType": "iPhone"]
        let data = (try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)) ?? Data()
        return .success(data)
    }

    public func pairDevice(host: String, port: UInt16, timeoutMs: UInt32) async -> Result<Data, PairingMessageError> {
        guard tunnelReachable else { return .failure(PairingMessageError("本地隧道未连通")) }
        let dict: [String: Any] = ["HostID": "MOCK-HOST", "DeviceName": "Simulator", "ProductType": "iPhone"]
        let data = (try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)) ?? Data()
        return .success(data)
    }

    public func lastErrorMessage() async -> String { "" }
}
