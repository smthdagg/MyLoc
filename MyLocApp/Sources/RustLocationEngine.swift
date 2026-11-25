import Foundation
import MyLocCore
import MyLocEngineFFI

/// Real engine implementation backed by `MyLocEngine.xcframework` (Rust `idevice`).
final class RustLocationEngine: LocationEngine, @unchecked Sendable {
    private let handle: OpaquePointer?
    private let queue = DispatchQueue(label: "com.myloc.engine.ffi", qos: .userInitiated)

    init() {
        self.handle = myloc_engine_create()
    }

    deinit {
        if let h = handle {
            myloc_engine_destroy(h)
        }
    }

    func probeTunnel(host: String, port: UInt16, timeoutMs: UInt32) async -> Result<Void, FailureStage> {
        await withCheckedContinuation { cont in
            queue.async {
                let code = host.withCString { cHost in
                    myloc_engine_probe_tunnel(cHost, port, timeoutMs)
                }
                cont.resume(returning: Self.mapResult(code, fallback: .tunnelUnreachable))
            }
        }
    }

    func connect(host: String, port: UInt16, pairingData: Data, timeoutMs: UInt32) async -> Result<Void, FailureStage> {
        await withCheckedContinuation { cont in
            queue.async { [handle] in
                guard let h = handle else {
                    cont.resume(returning: .failure(.tunnelCreate))
                    return
                }
                let code: Int32 = host.withCString { cHost in
                    pairingData.withUnsafeBytes { rawBuf in
                        guard let base = rawBuf.bindMemory(to: UInt8.self).baseAddress else {
                            return FailureStage.pairingRecord.rawValue
                        }
                        return myloc_engine_connect(h, cHost, port, base, pairingData.count, timeoutMs)
                    }
                }
                cont.resume(returning: Self.mapResult(code, fallback: .tunnelCreate))
            }
        }
    }

    func setLocation(latitude: Double, longitude: Double) async -> Result<Void, FailureStage> {
        await withCheckedContinuation { cont in
            queue.async { [handle] in
                guard let h = handle else {
                    cont.resume(returning: .failure(.activeWrite))
                    return
                }
                let code = myloc_engine_set_location(h, latitude, longitude)
                cont.resume(returning: Self.mapResult(code, fallback: .activeWrite))
            }
        }
    }

    func clearLocation() async -> Result<Void, FailureStage> {
        await withCheckedContinuation { cont in
            queue.async { [handle] in
                guard let h = handle else {
                    cont.resume(returning: .failure(.restore))
                    return
                }
                let code = myloc_engine_clear_location(h)
                cont.resume(returning: Self.mapResult(code, fallback: .restore))
            }
        }
    }

    func disconnect() async {
        await withCheckedContinuation { cont in
            queue.async { [handle] in
                if let h = handle {
                    _ = myloc_engine_disconnect(h)
                }
                cont.resume()
            }
        }
    }

    func startPairing(host: String, port: UInt16, timeoutMs: UInt32) async -> Result<Void, FailureStage> {
        await withCheckedContinuation { cont in
            queue.async { [handle] in
                guard let h = handle else {
                    cont.resume(returning: .failure(.tunnelUnreachable))
                    return
                }
                let code = host.withCString { cHost in
                    myloc_engine_start_pairing(h, cHost, port, timeoutMs)
                }
                cont.resume(returning: Self.mapResult(code, fallback: .tunnelUnreachable))
            }
        }
    }

    func submitPairingPin(_ pin: String) async -> Result<Data, FailureStage> {
        await withCheckedContinuation { cont in
            queue.async { [handle] in
                guard let h = handle else {
                    cont.resume(returning: .failure(.pairVerifyRejected))
                    return
                }
                let cap = 65536
                var buf = [UInt8](repeating: 0, count: cap)
                var outLen: Int = 0
                let code: Int32 = pin.withCString { cPin in
                    buf.withUnsafeMutableBufferPointer { ptr in
                        myloc_engine_submit_pairing_pin(h, cPin, ptr.baseAddress, cap, &outLen)
                    }
                }
                if code == 0 && outLen > 0 {
                    cont.resume(returning: .success(Data(buf.prefix(outLen))))
                } else {
                    cont.resume(returning: .failure(FailureStage(rawValue: code) ?? .pairVerifyRejected))
                }
            }
        }
    }

    func pairDevice(host: String, port: UInt16, timeoutMs: UInt32) async -> Result<Data, PairingMessageError> {
        await withCheckedContinuation { cont in
            queue.async { [handle] in
                guard let h = handle else {
                    cont.resume(returning: .failure(PairingMessageError("引擎未初始化")))
                    return
                }
                let cap = 65536
                var buf = [UInt8](repeating: 0, count: cap)
                var outLen: Int = 0
                let code: Int32 = host.withCString { cHost in
                    buf.withUnsafeMutableBufferPointer { ptr in
                        myloc_engine_pair_device(h, cHost, port, timeoutMs, ptr.baseAddress, cap, &outLen)
                    }
                }
                if code == 0 && outLen > 0 {
                    cont.resume(returning: .success(Data(buf.prefix(outLen))))
                } else {
                    var errBuf = [UInt8](repeating: 0, count: 512)
                    let n = errBuf.withUnsafeMutableBufferPointer { ptr in
                        myloc_engine_last_error_message(h, ptr.baseAddress, 512)
                    }
                    let msg = n > 0 ? String(decoding: errBuf.prefix(n), as: UTF8.self) : "配对失败 (code=\(code))"
                    cont.resume(returning: .failure(PairingMessageError(msg)))
                }
            }
        }
    }

    func lastErrorMessage() async -> String {
        await withCheckedContinuation { cont in
            queue.async { [handle] in
                guard let h = handle else {
                    cont.resume(returning: "")
                    return
                }
                var errBuf = [UInt8](repeating: 0, count: 512)
                let n = errBuf.withUnsafeMutableBufferPointer { ptr in
                    myloc_engine_last_error_message(h, ptr.baseAddress, 512)
                }
                let msg = n > 0 ? String(decoding: errBuf.prefix(n), as: UTF8.self) : ""
                cont.resume(returning: msg)
            }
        }
    }

    private static func mapResult(_ code: Int32, fallback: FailureStage) -> Result<Void, FailureStage> {
        if code == 0 { return .success(()) }
        return .failure(FailureStage(rawValue: code) ?? fallback)
    }
}
