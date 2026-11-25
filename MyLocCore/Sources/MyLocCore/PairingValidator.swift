import CryptoKit
import Foundation

/// Validates imported `.plist` / `.mobiledevicepairing` files and extracts summary metadata (FR-102, FR-106).
public enum PairingValidator {
    public enum ValidationError: Error, Equatable, Sendable {
        case emptyData
        case invalidPlist
        case missingRequiredFields
    }

    public static func validateAndSummarize(data: Data, importedAt: Date = Date()) throws -> PairingSummary {
        guard !data.isEmpty else {
            throw ValidationError.emptyData
        }
        let plistObj: Any
        do {
            plistObj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw ValidationError.invalidPlist
        }
        guard let dict = plistObj as? [String: Any], !dict.isEmpty else {
            throw ValidationError.invalidPlist
        }

        // Standard lockdownd / idevice pairing files contain HostID/SystemBUID or certificates,
        // and remote pairing files contain remote_pairing / UDID keys.
        let knownKeys: Set<String> = [
            "HostID", "SystemBUID", "DeviceCertificate", "HostCertificate",
            "RootCertificate", "UDID", "remote_pairing", "EscrowBag", "HostPrivateKey",
            "public_key", "private_key", "identifier", "alt_irk"
        ]
        let presentKeys = Set(dict.keys)
        guard !presentKeys.isDisjoint(with: knownKeys) else {
            throw ValidationError.missingRequiredFields
        }

        let deviceName = (dict["DeviceName"] as? String)
            ?? (dict["UDID"] as? String).map { "iOS 设备 (\($0.prefix(8)))" }
            ?? "已配对设备"
        let model = (dict["ProductType"] as? String)
            ?? (dict["DeviceClass"] as? String)
            ?? "iPhone"

        let digest = SHA256.hash(data: data)
        let fingerprint = digest.prefix(6).map { String(format: "%02X", $0) }.joined(separator: ":")

        return PairingSummary(
            deviceName: deviceName,
            model: model,
            fingerprint: fingerprint,
            importedAt: importedAt
        )
    }
}
