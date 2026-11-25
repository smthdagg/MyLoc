import Foundation

/// Failure stages aligned with Requirements §7.2 and Rust FFI status codes.
public enum FailureStage: Int32, Codable, CaseIterable, Equatable, Error, Sendable {
    case pairingRecord = 1
    case tunnelUnreachable = 2
    case serviceNotFound = 3
    case pairVerifyRejected = 4
    case tunnelCreate = 5
    case tunnelSecure = 6
    case rsdHandshake = 7
    case locationService = 8
    case initialWrite = 9
    case activeWrite = 10
    case restore = 11

    public var diagnosticCode: String {
        switch self {
        case .pairingRecord:      return "ERR_PAIRING_RECORD"
        case .tunnelUnreachable:  return "ERR_TUNNEL_UNREACHABLE"
        case .serviceNotFound:    return "ERR_SERVICE_NOT_FOUND"
        case .pairVerifyRejected: return "ERR_PAIR_VERIFY_REJECTED"
        case .tunnelCreate:       return "ERR_TUNNEL_CREATE"
        case .tunnelSecure:       return "ERR_TUNNEL_SECURE"
        case .rsdHandshake:       return "ERR_RSD_HANDSHAKE"
        case .locationService:    return "ERR_LOCATION_SERVICE"
        case .initialWrite:       return "ERR_INITIAL_WRITE"
        case .activeWrite:        return "ERR_ACTIVE_WRITE"
        case .restore:            return "ERR_RESTORE"
        }
    }

    public var userMessageZh: String {
        switch self {
        case .pairingRecord:
            return "配对记录缺失或损坏，请重新导入有效的配对文件。"
        case .tunnelUnreachable:
            return "本地隧道未连通，请先打开 LocalDevVPN 建立连接后再重试。"
        case .serviceNotFound:
            return "未发现本机开发者服务，请确认已开启“开发者模式”且隧道正常。"
        case .pairVerifyRejected:
            return "配对校验被设备拒绝，配对记录可能已失效，请重新导入。"
        case .tunnelCreate:
            return "建立本地开发者隧道失败，请检查 LocalDevVPN 连接状态。"
        case .tunnelSecure:
            return "安全信道握手失败，请重启 LocalDevVPN 后重试。"
        case .rsdHandshake:
            return "远程服务发现握手超时，请确认设备未处于锁屏受限状态。"
        case .locationService:
            return "无法打开位置模拟服务，请确认系统版本与开发者镜像状态。"
        case .initialWrite:
            return "首次写入坐标失败，请检查连接后重试。"
        case .activeWrite:
            return "会话中断，坐标写入失败，可尝试重新开始会话。"
        case .restore:
            return "清除模拟位置失败，请重新连接后再次点击“停止并恢复”。"
        }
    }
}

/// Session lifecycle states aligned with Requirements §7.1.
public enum SessionState: Equatable, Sendable {
    case idle
    case preparing
    case tunnel
    case discovering
    case connecting
    case active
    case stopping
    case failed(FailureStage)

    public var isBusy: Bool {
        switch self {
        case .preparing, .tunnel, .discovering, .connecting, .stopping:
            return true
        default:
            return false
        }
    }

    public var displayTextZh: String {
        switch self {
        case .idle:        return "就绪"
        case .preparing:   return "准备中"
        case .tunnel:      return "检查隧道"
        case .discovering: return "发现服务"
        case .connecting:  return "建立连接"
        case .active:      return "位置模拟中"
        case .stopping:    return "正在恢复"
        case .failed(let stage): return "失败 (\(stage.diagnosticCode))"
        }
    }
}

public struct DiagnosticEvent: Equatable, Sendable {
    public let timestamp: Date
    public let stage: String
    public let code: String

    public init(timestamp: Date = Date(), stage: String, code: String) {
        self.timestamp = timestamp
        self.stage = stage
        self.code = code
    }
}

/// Builds sanitized plain-text diagnostics (FR-803, FR-806, AC-10).
/// Strictly excludes coordinates, pairing keys, PINs, and device names.
public enum DiagnosticsBuilder {
    public static func build(
        appVersion: String,
        osVersion: String,
        hasPairing: Bool,
        tunnelReachable: Bool,
        sessionState: SessionState,
        lastFailure: FailureStage?,
        events: [DiagnosticEvent]
    ) -> String {
        let formatter = ISO8601DateFormatter()
        var lines: [String] = [
            "MyLoc Diagnostics",
            "app_version=\(appVersion)",
            "ios_version=\(osVersion)",
            "pairing_configured=\(hasPairing)",
            "tunnel_reachable=\(tunnelReachable)",
            "session_state=\(stateTag(sessionState))",
            "last_failure=\(lastFailure?.diagnosticCode ?? "NONE")",
            "timeline:"
        ]
        for ev in events.suffix(20) {
            lines.append("  \(formatter.string(from: ev.timestamp)) [\(ev.stage)] \(ev.code)")
        }
        return lines.joined(separator: "\n")
    }

    private static func stateTag(_ state: SessionState) -> String {
        switch state {
        case .idle: return "idle"
        case .preparing: return "preparing"
        case .tunnel: return "tunnel"
        case .discovering: return "discovering"
        case .connecting: return "connecting"
        case .active: return "active"
        case .stopping: return "stopping"
        case .failed(let f): return "failed:\(f.diagnosticCode)"
        }
    }
}
