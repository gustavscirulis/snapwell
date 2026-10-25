import Foundation

/// Only automation builds can redirect storage or replace credentials.
enum AutomationEnvironment {
    static var isEnabled: Bool {
        #if SNAPWELL_AUTOMATION
        true
        #else
        false
        #endif
    }

    static func argument(_ name: String) -> String? {
        guard isEnabled,
              let index = ProcessInfo.processInfo.arguments.firstIndex(of: name),
              ProcessInfo.processInfo.arguments.indices.contains(index + 1) else { return nil }
        return ProcessInfo.processInfo.arguments[index + 1]
    }

    static var usesFixtureProviders: Bool {
        argument("--snapwell-fixture") != nil
    }

    static let rootURL: URL = {
        let id = argument("--snapwell-test-id") ?? UUID().uuidString
        precondition(id.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapwellAutomation", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        if isEnabled {
            do {
                for name in ["images", "metadata", "thumbnails", "queue", "incoming",
                             ".trash/images", ".trash/metadata", ".trash/thumbnails"] {
                    try FileManager.default.createDirectory(
                        at: url.appendingPathComponent(name), withIntermediateDirectories: true)
                }
            } catch { fatalError("Cannot create isolated automation storage: \(error)") }
        }
        return url
    }()

    private static let lock = NSLock()
    nonisolated(unsafe) private static var keys: [String: String] = [:]

    static func key(_ service: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return keys[service]
    }

    static func setKey(_ value: String?, service: String) {
        lock.lock()
        defer { lock.unlock() }
        keys[service] = value
    }
}
