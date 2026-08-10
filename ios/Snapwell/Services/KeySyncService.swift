import Foundation
import os

private let logger = Logger(subsystem: "co.snapwell.app", category: "KeySync")

enum KeySource: String {
    case iCloudSync
    case local
    case none
}

@MainActor
final class KeySyncService: ObservableObject {

    static let shared = KeySyncService()
    nonisolated static let providerDefaultsKey = "aiProvider"
    nonisolated static let autoModelValue = "auto"

    private static let maskedPlaceholder = String(repeating: "•", count: 48)
    private static let legacyMigrationKey = "inAppAISettingsMigration_v1"
    private static let lastImportedAtKey = "keySyncLastImportedAt"

    @Published private(set) var isUnlocked = false
    @Published private(set) var activeProvider: String?
    @Published private(set) var activeModel: String?
    @Published private(set) var keySource: KeySource = .none

    private var decryptedKeys: [String: String] = [:]
    private let fileName = ".apikeys.encrypted"

    private init() {}

    // MARK: - Main sync entry points

    func checkForKeys(rootURL: URL) {
        migrateLegacySettingsIfNeeded()

        if let payload = readiCloudPayload(rootURL: rootURL),
           Self.shouldImport(
               payloadUpdatedAt: payload.updatedAt,
               lastImportedAt: UserDefaults.standard.double(forKey: Self.lastImportedAtKey)
           ) {
            importPayload(payload)
            return
        }

        reloadLocalState(source: .local)
    }

    /// Retained as a compatibility entry point for launches without a resolved library URL.
    func checkForSettingsKeys() {
        migrateLegacySettingsIfNeeded()
        reloadLocalState(source: .local)
    }

    // MARK: - Settings mutations

    func selectProvider(_ provider: AIProvider, rootURL: URL?) {
        UserDefaults.standard.set(provider.rawValue, forKey: Self.providerDefaultsKey)
        persistLocalEdit(rootURL: rootURL)
    }

    func setModel(_ model: String, for provider: AIProvider, rootURL: URL?) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(
            trimmed.isEmpty ? Self.autoModelValue : trimmed,
            forKey: Self.modelDefaultsKey(for: provider)
        )
        persistLocalEdit(rootURL: rootURL)
    }

    func saveAPIKey(_ key: String, for provider: AIProvider, rootURL: URL?) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try KeychainService.set(key: trimmed, forService: provider.keychainService)
        UserDefaults.standard.set(provider.rawValue, forKey: Self.providerDefaultsKey)
        if UserDefaults.standard.object(forKey: Self.modelDefaultsKey(for: provider)) == nil {
            UserDefaults.standard.set(Self.autoModelValue, forKey: Self.modelDefaultsKey(for: provider))
        }

        persistLocalEdit(rootURL: rootURL)
    }

    func removeAPIKey(for provider: AIProvider, rootURL: URL?) throws {
        try KeychainService.delete(service: provider.keychainService)
        persistLocalEdit(rootURL: rootURL)
    }

    func hasAPIKey(for provider: AIProvider) -> Bool {
        KeychainService.exists(service: provider.keychainService)
    }

    func modelSelection(for provider: AIProvider) -> String {
        let stored = UserDefaults.standard.string(forKey: Self.modelDefaultsKey(for: provider))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stored, !stored.isEmpty else { return Self.autoModelValue }
        return stored
    }

    nonisolated static func modelDefaultsKey(for provider: AIProvider) -> String {
        "\(provider.rawValue)Model"
    }

    nonisolated static func shouldImport(payloadUpdatedAt: Date, lastImportedAt: TimeInterval) -> Bool {
        payloadUpdatedAt.timeIntervalSince1970 > lastImportedAt
    }

    // MARK: - Key accessors

    func apiKey(for provider: String) -> String? {
        decryptedKeys[provider]
    }

    func activeAPIKey() -> String? {
        guard let provider = activeProvider else { return nil }
        return decryptedKeys[provider]
    }

    // MARK: - Legacy migration

    func migrateLegacySettingsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.legacyMigrationKey) else {
            removeLegacySettings(from: defaults)
            return
        }

        let legacyProviderRaw = defaults.string(forKey: "settings_provider")
        let legacyProvider = legacyProviderRaw.flatMap(AIProvider.init(rawValue:))
        let legacyModel = defaults.string(forKey: "settings_model")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyKey = defaults.string(forKey: "settings_apiKey")?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let provider = legacyProvider {
            if defaults.object(forKey: Self.providerDefaultsKey) == nil {
                defaults.set(provider.rawValue, forKey: Self.providerDefaultsKey)
            }
            if defaults.object(forKey: Self.modelDefaultsKey(for: provider)) == nil {
                defaults.set(
                    legacyModel?.isEmpty == false ? legacyModel : Self.autoModelValue,
                    forKey: Self.modelDefaultsKey(for: provider)
                )
            }
            if let legacyKey,
               !legacyKey.isEmpty,
               legacyKey != Self.maskedPlaceholder {
                try? KeychainService.set(key: legacyKey, forService: provider.keychainService)
            }
        }

        if defaults.object(forKey: Self.providerDefaultsKey) == nil {
            defaults.set(AIProvider.openai.rawValue, forKey: Self.providerDefaultsKey)
        }

        removeLegacySettings(from: defaults)
        defaults.set(true, forKey: Self.legacyMigrationKey)
    }

    private func removeLegacySettings(from defaults: UserDefaults) {
        defaults.removeObject(forKey: "settings_apiKey")
        defaults.removeObject(forKey: "settings_provider")
        defaults.removeObject(forKey: "settings_model")
        defaults.removeObject(forKey: "settings_lastSyncedKeyHash")
    }

    // MARK: - Local and iCloud state

    private var selectedProvider: AIProvider {
        let rawValue = UserDefaults.standard.string(forKey: Self.providerDefaultsKey)
        return rawValue.flatMap(AIProvider.init(rawValue:)) ?? .openai
    }

    private func loadAllKeysFromKeychain() -> [String: String] {
        var keys: [String: String] = [:]
        for provider in AIProvider.allCases {
            if let key = try? KeychainService.get(service: provider.keychainService), !key.isEmpty {
                keys[provider.rawValue] = key
            }
        }
        return keys
    }

    private func reloadLocalState(source: KeySource) {
        let provider = selectedProvider
        let keys = loadAllKeysFromKeychain()
        decryptedKeys = keys
        activeProvider = provider.rawValue
        activeModel = modelSelection(for: provider)
        isUnlocked = keys[provider.rawValue]?.isEmpty == false
        keySource = keys.isEmpty ? .none : source
        logger.info("Using \(source.rawValue, privacy: .public) settings — provider: \(provider.rawValue, privacy: .private)")
    }

    private func importPayload(_ payload: KeySyncPayload) {
        let defaults = UserDefaults.standard

        if payload.provider == "none" {
            clearKeychainKeys()
            defaults.set(AIProvider.openai.rawValue, forKey: Self.providerDefaultsKey)
        } else if let provider = AIProvider(rawValue: payload.provider) {
            // The payload contains the complete key set. Deleting absent entries propagates
            // provider-specific key removal instead of resurrecting stale local credentials.
            for candidate in AIProvider.allCases {
                if let key = payload.keys[candidate.rawValue], !key.isEmpty {
                    try? KeychainService.set(key: key, forService: candidate.keychainService)
                } else {
                    try? KeychainService.delete(service: candidate.keychainService)
                }
            }
            defaults.set(provider.rawValue, forKey: Self.providerDefaultsKey)
            let model = payload.model.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(
                model.isEmpty ? Self.autoModelValue : model,
                forKey: Self.modelDefaultsKey(for: provider)
            )
        } else {
            logger.warning("Ignoring iCloud payload with unknown provider: \(payload.provider, privacy: .public)")
            reloadLocalState(source: .local)
            return
        }

        defaults.set(payload.updatedAt.timeIntervalSince1970, forKey: Self.lastImportedAtKey)
        reloadLocalState(source: .iCloudSync)
    }

    private func clearKeychainKeys() {
        for provider in AIProvider.allCases {
            try? KeychainService.delete(service: provider.keychainService)
        }
    }

    private func persistLocalEdit(rootURL: URL?) {
        let updatedAt = Date.now
        UserDefaults.standard.set(updatedAt.timeIntervalSince1970, forKey: Self.lastImportedAtKey)
        reloadLocalState(source: .local)
        syncToiCloudIfAvailable(rootURL: rootURL, updatedAt: updatedAt)
    }

    private func syncToiCloudIfAvailable(rootURL: URL?, updatedAt: Date) {
        guard FileSystemManager.shared?.isUsingiCloud == true, let rootURL else { return }

        let provider = selectedProvider
        let payload = KeySyncPayload(
            provider: provider.rawValue,
            model: modelSelection(for: provider),
            keys: loadAllKeysFromKeychain(),
            updatedAt: updatedAt
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let plaintext = try encoder.encode(payload)
            let encrypted = try KeySyncCrypto.encrypt(plaintext)
            let fileURL = rootURL.appendingPathComponent(fileName)
            try encrypted.write(to: fileURL, options: .atomic)
            logger.info("Wrote keys to iCloud — provider: \(provider.rawValue, privacy: .private)")
        } catch {
            logger.error("Failed to write to iCloud: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func readiCloudPayload(rootURL: URL) -> KeySyncPayload? {
        let fileURL = rootURL.appendingPathComponent(fileName)
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: fileURL.path) {
            let directory = fileURL.deletingLastPathComponent()
            for name in [".\(fileName).icloud", "\(fileName).icloud"] {
                let placeholderURL = directory.appendingPathComponent(name)
                if fileManager.fileExists(atPath: placeholderURL.path) {
                    try? fileManager.startDownloadingUbiquitousItem(at: fileURL)
                    logger.info("Encrypted file is an iCloud placeholder; triggered download")
                    break
                }
            }
            return nil
        }

        do {
            let encrypted = try Data(contentsOf: fileURL)
            let decrypted = try KeySyncCrypto.decrypt(encrypted)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(KeySyncPayload.self, from: decrypted)
        } catch {
            logger.error("Decryption failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
