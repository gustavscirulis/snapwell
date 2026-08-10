import Testing
import Foundation
import CryptoKit
@testable import Snapwell

@Suite("KeySyncService", .serialized, .tags(.crypto))
struct KeySyncServiceTests {

    // MARK: - KeySyncPayload roundtrip

    @Test("KeySyncPayload encodes all fields")
    func payloadEncode() throws {
        let payload = KeySyncPayload(
            provider: "anthropic",
            model: "claude-sonnet-4-5",
            keys: ["anthropic": "test-ant-key", "openai": "test-oai-key"],
            updatedAt: Date(timeIntervalSince1970: 1700000000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["provider"] as? String == "anthropic")
        #expect(json?["model"] as? String == "claude-sonnet-4-5")
        let keys = json?["keys"] as? [String: String]
        #expect(keys?["anthropic"] == "test-ant-key")
        #expect(keys?["openai"] == "test-oai-key")
    }

    @Test("KeySyncPayload decode roundtrip")
    func payloadRoundtrip() throws {
        let original = KeySyncPayload(
            provider: "openai",
            model: "gpt-4o",
            keys: ["openai": "test-key-123"],
            updatedAt: Date(timeIntervalSince1970: 1700000000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeySyncPayload.self, from: data)

        #expect(decoded.provider == "openai")
        #expect(decoded.model == "gpt-4o")
        #expect(decoded.keys["openai"] == "test-key-123")
    }

    @Test("KeySyncPayload with empty keys dict")
    func emptyKeys() throws {
        let payload = KeySyncPayload(
            provider: "openai",
            model: "gpt-4o",
            keys: [:],
            updatedAt: Date()
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(KeySyncPayload.self, from: data)

        #expect(decoded.keys.isEmpty)
        let hasAnyKey = decoded.keys.values.contains { !$0.isEmpty }
        #expect(hasAnyKey == false)
    }

    @Test("KeySyncPayload with empty string values")
    func emptyStringValues() throws {
        let payload = KeySyncPayload(
            provider: "openai",
            model: "gpt-4o",
            keys: ["openai": "", "anthropic": "test-valid-key"],
            updatedAt: Date()
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(KeySyncPayload.self, from: data)

        let hasAnyKey = decoded.keys.values.contains { !$0.isEmpty }
        #expect(hasAnyKey == true)
    }

    @Test("KeySyncPayload all empty string values means not unlocked")
    func allEmptyStringValues() throws {
        let payload = KeySyncPayload(
            provider: "openai",
            model: "gpt-4o",
            keys: ["openai": "", "anthropic": ""],
            updatedAt: Date()
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(KeySyncPayload.self, from: data)

        let hasAnyKey = decoded.keys.values.contains { !$0.isEmpty }
        #expect(hasAnyKey == false)
    }

    // MARK: - Full encrypt/decrypt/decode pipeline

    @Test("End-to-end: encrypt payload, decrypt, decode")
    func endToEndPipeline() throws {
        let testKey = SymmetricKey(size: .bits256)
        let payload = KeySyncPayload(
            provider: "gemini",
            model: "gemini-2.0-flash",
            keys: ["gemini": "AIza-test-key"],
            updatedAt: Date(timeIntervalSince1970: 1700000000)
        )

        let encoded = try JSONEncoder().encode(payload)
        let encrypted = try KeySyncCrypto.encrypt(encoded, using: testKey)

        let decrypted = try KeySyncCrypto.decrypt(encrypted, using: testKey)
        let decoded = try JSONDecoder().decode(KeySyncPayload.self, from: decrypted)

        #expect(decoded.provider == "gemini")
        #expect(decoded.model == "gemini-2.0-flash")
        #expect(decoded.keys["gemini"] == "AIza-test-key")

        let hasAnyKey = decoded.keys.values.contains { !$0.isEmpty }
        #expect(hasAnyKey == true)
    }

    // MARK: - iCloud placeholder detection

    @Test("iCloud placeholder names for dotted files")
    func iCloudPlaceholderNames() {
        let fileName = ".apikeys.encrypted"
        let placeholderNames = [
            ".\(fileName).icloud",
            "\(fileName).icloud"
        ]
        #expect(placeholderNames[0] == "..apikeys.encrypted.icloud")
        #expect(placeholderNames[1] == ".apikeys.encrypted.icloud")
    }

    // MARK: - Legacy Settings.bundle migration

    private func cleanupDefaults(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: "settings_apiKey")
        defaults.removeObject(forKey: "settings_provider")
        defaults.removeObject(forKey: "settings_model")
        defaults.removeObject(forKey: "settings_lastSyncedKeyHash")
        defaults.removeObject(forKey: "settings_defaults_v2")
        defaults.removeObject(forKey: "inAppAISettingsMigration_v1")
        defaults.removeObject(forKey: "keySyncLastImportedAt")
        defaults.removeObject(forKey: KeySyncService.providerDefaultsKey)
        for provider in AIProvider.allCases {
            defaults.removeObject(forKey: KeySyncService.modelDefaultsKey(for: provider))
        }
    }

    private func cleanupKeychain() {
        for provider in AIProvider.allCases {
            try? KeychainService.delete(service: provider.rawValue)
        }
    }

    @Test("Legacy non-empty key unlocks service")
    @MainActor func legacyKeyUnlocks() async {
        let defaults = UserDefaults.standard
        cleanupDefaults(defaults)
        cleanupKeychain()
        defer { cleanupDefaults(defaults); cleanupKeychain() }

        defaults.set("test-ant-key-123", forKey: "settings_apiKey")
        defaults.set("anthropic", forKey: "settings_provider")
        defaults.set("", forKey: "settings_model")

        let service = KeySyncService.shared
        service.checkForSettingsKeys()

        #expect(service.isUnlocked == true)
        #expect(service.keySource == .local)
        #expect(service.activeProvider == "anthropic")
        #expect(service.activeModel == "auto")
        #expect(service.activeAPIKey() == "test-ant-key-123")
    }

    @Test("Legacy empty key does not unlock")
    @MainActor func legacyEmptyKey() async {
        let defaults = UserDefaults.standard
        cleanupDefaults(defaults)
        cleanupKeychain()
        defer { cleanupDefaults(defaults); cleanupKeychain() }

        defaults.set("", forKey: "settings_apiKey")
        defaults.set("openai", forKey: "settings_provider")

        let service = KeySyncService.shared
        service.checkForSettingsKeys()

        #expect(service.isUnlocked == false)
        #expect(service.keySource == .none)
    }

    @Test("Legacy whitespace-only key is treated as empty")
    @MainActor func legacyWhitespaceKey() async {
        let defaults = UserDefaults.standard
        cleanupDefaults(defaults)
        cleanupKeychain()
        defer { cleanupDefaults(defaults); cleanupKeychain() }

        defaults.set("   ", forKey: "settings_apiKey")
        defaults.set("openai", forKey: "settings_provider")

        let service = KeySyncService.shared
        service.checkForSettingsKeys()

        #expect(service.isUnlocked == false)
        #expect(service.keySource == .none)
    }

    @Test("Legacy unknown provider is rejected")
    @MainActor func legacyUnknownProvider() async {
        let defaults = UserDefaults.standard
        cleanupDefaults(defaults)
        cleanupKeychain()
        defer { cleanupDefaults(defaults); cleanupKeychain() }

        defaults.set("test-key-123", forKey: "settings_apiKey")
        defaults.set("invalid_provider", forKey: "settings_provider")

        let service = KeySyncService.shared
        service.checkForSettingsKeys()

        #expect(service.isUnlocked == false)
        #expect(service.keySource == .none)
    }

    @Test("Legacy concrete model is preserved")
    @MainActor func legacyConcreteModel() async {
        let defaults = UserDefaults.standard
        cleanupDefaults(defaults)
        cleanupKeychain()
        defer { cleanupDefaults(defaults); cleanupKeychain() }

        defaults.set("test-key-123", forKey: "settings_apiKey")
        defaults.set("openai", forKey: "settings_provider")
        defaults.set("gpt-4o-mini", forKey: "settings_model")

        let service = KeySyncService.shared
        service.checkForSettingsKeys()

        #expect(service.isUnlocked == true)
        #expect(service.activeModel == "gpt-4o-mini")
    }

    @Test("Legacy provider 'none' does not unlock")
    @MainActor func legacyNoneProvider() async {
        let defaults = UserDefaults.standard
        cleanupDefaults(defaults)
        cleanupKeychain()
        defer { cleanupDefaults(defaults); cleanupKeychain() }

        defaults.set("test-key-123", forKey: "settings_apiKey")
        defaults.set("none", forKey: "settings_provider")

        let service = KeySyncService.shared
        service.checkForSettingsKeys()

        #expect(service.isUnlocked == false)
        #expect(service.keySource == .none)
    }

    @Test("Legacy plaintext key is removed after migration")
    @MainActor func legacyMigrationRemovesPlaintext() async {
        let defaults = UserDefaults.standard
        cleanupDefaults(defaults)
        cleanupKeychain()
        defer { cleanupDefaults(defaults); cleanupKeychain() }

        defaults.set("test-key-xyz", forKey: "settings_apiKey")
        defaults.set("anthropic", forKey: "settings_provider")

        let service = KeySyncService.shared
        service.checkForSettingsKeys()

        #expect(defaults.object(forKey: "settings_apiKey") == nil)
    }

    @Test("Legacy masked placeholder is ignored on subsequent reads")
    @MainActor func legacyPlaceholderIgnored() async {
        let defaults = UserDefaults.standard
        cleanupDefaults(defaults)
        cleanupKeychain()
        defer { cleanupDefaults(defaults); cleanupKeychain() }

        defaults.set("test-key-abc", forKey: "settings_apiKey")
        defaults.set("openai", forKey: "settings_provider")

        let service = KeySyncService.shared
        service.checkForSettingsKeys()

        #expect(service.isUnlocked == true)
        #expect(service.activeAPIKey() == "test-key-abc")

        #expect(defaults.object(forKey: "settings_apiKey") == nil)

        service.checkForSettingsKeys()
        #expect(service.isUnlocked == true)
    }

    @Test("Legacy model 'auto' sets activeModel to auto")
    @MainActor func legacyAutoModel() async {
        let defaults = UserDefaults.standard
        cleanupDefaults(defaults)
        cleanupKeychain()
        defer { cleanupDefaults(defaults); cleanupKeychain() }

        defaults.set("test-key-123", forKey: "settings_apiKey")
        defaults.set("anthropic", forKey: "settings_provider")
        defaults.set("auto", forKey: "settings_model")

        let service = KeySyncService.shared
        service.checkForSettingsKeys()

        #expect(service.isUnlocked == true)
        #expect(service.activeModel == "auto")
    }

    @Test("Migration is idempotent and preserves the first imported key")
    @MainActor func migrationIsIdempotent() async {
        let defaults = UserDefaults.standard
        cleanupDefaults(defaults)
        cleanupKeychain()
        defer { cleanupDefaults(defaults); cleanupKeychain() }

        defaults.set("first-key", forKey: "settings_apiKey")
        defaults.set("openai", forKey: "settings_provider")

        let service = KeySyncService.shared
        service.checkForSettingsKeys()

        defaults.set("second-key", forKey: "settings_apiKey")
        service.checkForSettingsKeys()

        #expect(service.activeAPIKey() == "first-key")
        #expect(defaults.object(forKey: "settings_apiKey") == nil)
    }

    @Test("Provider switching retains independent keys and models")
    @MainActor func providerSwitchRetainsSettings() async throws {
        let defaults = UserDefaults.standard
        cleanupDefaults(defaults)
        cleanupKeychain()
        defer { cleanupDefaults(defaults); cleanupKeychain() }

        let service = KeySyncService.shared
        service.checkForSettingsKeys()
        try service.saveAPIKey("openai-key", for: .openai, rootURL: nil)
        service.setModel("gpt-4o", for: .openai, rootURL: nil)
        try service.saveAPIKey("anthropic-key", for: .anthropic, rootURL: nil)
        service.setModel("claude-sonnet-5", for: .anthropic, rootURL: nil)

        #expect(service.activeProvider == "anthropic")
        #expect(service.activeAPIKey() == "anthropic-key")
        #expect(service.activeModel == "claude-sonnet-5")

        service.selectProvider(.openai, rootURL: nil)

        #expect(service.activeAPIKey() == "openai-key")
        #expect(service.activeModel == "gpt-4o")
        #expect(service.hasAPIKey(for: .anthropic))
    }

    @Test("Removing the selected key disables analysis without deleting other providers")
    @MainActor func removeSelectedKeyRetainsOthers() async throws {
        let defaults = UserDefaults.standard
        cleanupDefaults(defaults)
        cleanupKeychain()
        defer { cleanupDefaults(defaults); cleanupKeychain() }

        let service = KeySyncService.shared
        service.checkForSettingsKeys()
        try service.saveAPIKey("openai-key", for: .openai, rootURL: nil)
        try service.saveAPIKey("gemini-key", for: .gemini, rootURL: nil)
        try service.removeAPIKey(for: .gemini, rootURL: nil)

        #expect(service.activeProvider == "gemini")
        #expect(service.isUnlocked == false)
        #expect(service.activeAPIKey() == nil)
        #expect(service.hasAPIKey(for: .openai))
    }

    @Test("Local edits reject older iCloud payloads and allow newer ones")
    @MainActor func localEditAdvancesSyncWatermark() async {
        let defaults = UserDefaults.standard
        cleanupDefaults(defaults)
        cleanupKeychain()
        defer { cleanupDefaults(defaults); cleanupKeychain() }

        let service = KeySyncService.shared
        service.checkForSettingsKeys()
        let beforeEdit = Date.now
        service.setModel("gpt-4o", for: .openai, rootURL: nil)

        let watermark = defaults.double(forKey: "keySyncLastImportedAt")
        #expect(watermark >= beforeEdit.timeIntervalSince1970)
        #expect(KeySyncService.shouldImport(
            payloadUpdatedAt: Date(timeIntervalSince1970: watermark - 1),
            lastImportedAt: watermark
        ) == false)
        #expect(KeySyncService.shouldImport(
            payloadUpdatedAt: Date(timeIntervalSince1970: watermark + 1),
            lastImportedAt: watermark
        ) == true)
    }
}
