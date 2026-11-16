import Foundation
import os

private let logger = Logger(subsystem: "co.snapwell", category: "KeySync")

enum KeySyncService {

    private static let fileName = ".apikeys.encrypted"
    private static let lastImportedAtKey = "keySyncLastImportedAt"

    /// Returns true when startup can safely create a local default immediately.
    /// A downloaded synced choice is imported first; an evicted choice is left
    /// for the async resolver so it cannot be overwritten by startup.
    static func resolveImmediatelyAvailableInitialSettings() -> Bool {
        guard !AutomationEnvironment.isEnabled else { return true }
        guard MediaStorageService.shared.isUsingiCloud else { return true }

        let url = MediaStorageService.shared.baseURL.appendingPathComponent(fileName)
        switch ICloudFile.downloadState(of: url, isUsingiCloud: true) {
        case .notPresent:
            return true
        case .downloaded:
            syncFromiCloud()
            return true
        case .downloading:
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            return false
        }
    }

    /// Resolve an existing iCloud selection before creating a device-local default.
    /// An evicted settings file is downloaded and given the same brief foreground
    /// retry window used by iOS.
    static func resolveInitialSettingsFromiCloud() async -> Bool {
        guard !AutomationEnvironment.isEnabled else { return true }
        guard MediaStorageService.shared.isUsingiCloud else { return true }

        let url = MediaStorageService.shared.baseURL.appendingPathComponent(fileName)
        switch ICloudFile.downloadState(of: url, isUsingiCloud: true) {
        case .notPresent:
            return true
        case .downloaded:
            syncFromiCloud()
            return true
        case .downloading:
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }

        for delay in [
            Duration.milliseconds(350), .seconds(1), .seconds(2),
            .seconds(4), .seconds(8), .seconds(15)
        ] {
            do {
                try await Task.sleep(for: delay)
            } catch {
                return false
            }
            guard !Task.isCancelled else { return false }
            if ICloudFile.downloadState(of: url, isUsingiCloud: true) == .downloaded {
                syncFromiCloud()
                return true
            }
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        return false
    }

    // MARK: - Write local keys to iCloud

    static func syncToiCloud() {
        guard !AutomationEnvironment.isEnabled else { return }
        guard MediaStorageService.shared.isUsingiCloud else { return }

        let url = MediaStorageService.shared.baseURL.appendingPathComponent(fileName)

        var keys: [String: String] = [:]
        for provider in AIProvider.credentialProviders {
            if let key = try? KeychainService.get(service: provider.keychainService), !key.isEmpty {
                keys[provider.rawValue] = key
            }
        }

        let currentProvider = AIProvider.initializeDefaultIfNeeded().rawValue
        let modelKey = "\(currentProvider)Model"
        let currentModel = UserDefaults.standard.string(forKey: modelKey) ?? "auto"

        let payload = KeySyncPayload(
            provider: currentProvider,
            model: currentModel,
            keys: keys,
            updatedAt: .now
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let plaintext = try encoder.encode(payload)
            let encrypted = try KeySyncCrypto.encrypt(plaintext)
            try encrypted.write(to: url, options: .atomic)
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: lastImportedAtKey)
            logger.info("Wrote encrypted keys to iCloud")
        } catch {
            logger.error("Failed to sync: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Read keys from iCloud (written by iOS or another Mac)

    static func syncFromiCloud() {
        guard !AutomationEnvironment.isEnabled else { return }
        guard MediaStorageService.shared.isUsingiCloud else { return }

        let url = MediaStorageService.shared.baseURL.appendingPathComponent(fileName)
        guard ICloudFile.downloadState(of: url, isUsingiCloud: true) == .downloaded else {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            return
        }

        do {
            let encrypted = try Data(contentsOf: url)
            let decrypted = try KeySyncCrypto.decrypt(encrypted)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(KeySyncPayload.self, from: decrypted)

            let lastImported = UserDefaults.standard.double(forKey: lastImportedAtKey)
            let payloadTimestamp = payload.updatedAt.timeIntervalSince1970

            let hasLocalSelection = UserDefaults.standard.string(forKey: "aiProvider") != nil
            guard !hasLocalSelection || payloadTimestamp > lastImported else {
                logger.info("iCloud file not newer than last import, skipping")
                return
            }

            if payload.provider == "none" {
                for provider in AIProvider.credentialProviders {
                    try? KeychainService.delete(service: provider.keychainService)
                }
                UserDefaults.standard.set(payloadTimestamp, forKey: lastImportedAtKey)
                NotificationCenter.default.post(name: .apiKeySaved, object: nil)
                logger.info("Imported key removal from iCloud")
                return
            }

            // The payload is a complete key snapshot. Remove entries that are absent so
            // deleting one provider on iOS does not leave a stale credential on the Mac.
            for provider in AIProvider.credentialProviders {
                if let key = payload.keys[provider.rawValue], !key.isEmpty {
                    try KeychainService.set(key: key, forService: provider.keychainService)
                } else {
                    try KeychainService.delete(service: provider.keychainService)
                }
            }

            guard let provider = AIProvider(rawValue: payload.provider) else {
                logger.warning("Ignoring iCloud payload with unknown provider: \(payload.provider, privacy: .public)")
                return
            }
            UserDefaults.standard.set(provider.rawValue, forKey: "aiProvider")
            let modelKey = "\(provider.rawValue)Model"
            UserDefaults.standard.set(
                provider == .appleIntelligence ? provider.defaultModel : payload.model,
                forKey: modelKey
            )

            UserDefaults.standard.set(payloadTimestamp, forKey: lastImportedAtKey)

            NotificationCenter.default.post(name: .apiKeySaved, object: nil)
            logger.info("Imported keys from iCloud — provider: \(payload.provider, privacy: .private)")
        } catch {
            logger.error("Failed to read from iCloud: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Remove sync file

    static func removeSyncFile() {
        guard MediaStorageService.shared.isUsingiCloud else { return }
        let url = MediaStorageService.shared.baseURL.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
        logger.info("Removed encrypted keys from iCloud")
    }
}
