import Foundation
import CryptoKit

public typealias JSON = [String: Any]
public struct ReleaseError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct Credentials {
    public let keyID: String
    public let issuerID: String?
    public let keyURL: URL

    public init(environment: [String: String] = ProcessInfo.processInfo.environment,
                configurationURL: URL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".appstoreconnect/snapwell.json")) throws {
        struct Configuration: Decodable {
            let key_path: String?
            let key_id: String?
            let issuer_id: String?
        }
        // A complete environment configuration is independent of any local file,
        // including when an individual key intentionally omits the issuer ID.
        var configuration: Configuration?
        if environment["ASC_KEY_PATH"] == nil || environment["ASC_KEY_ID"] == nil {
            if FileManager.default.fileExists(atPath: configurationURL.path) {
                do {
                    configuration = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configurationURL))
                } catch {
                    // Do not echo configuration contents in diagnostics.
                    throw ReleaseError("Could not read App Store Connect configuration at \(configurationURL.path). Expected JSON with key_path, key_id and optional issuer_id.")
                }
            }
        }
        func nonempty(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        guard let path = nonempty(environment["ASC_KEY_PATH"] ?? configuration?.key_path),
              let key = nonempty(environment["ASC_KEY_ID"] ?? configuration?.key_id) else {
            throw ReleaseError("Configure ~/.appstoreconnect/snapwell.json or set ASC_KEY_PATH and ASC_KEY_ID; team keys also need ASC_ISSUER_ID. Keys stay outside the repo.")
        }
        keyURL = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        keyID = key
        issuerID = nonempty(environment["ASC_ISSUER_ID"] ?? configuration?.issuer_id)
    }

    public func token(now: Date = Date()) throws -> String {
        func encode(_ object: JSON) throws -> String {
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).base64URL
        }
        var claims: JSON = ["aud": "appstoreconnect-v1", "iat": Int(now.timeIntervalSince1970),
                            "exp": Int(now.timeIntervalSince1970) + 600]
        if let issuerID { claims["iss"] = issuerID } else { claims["sub"] = "user" }
        let content = try encode(["alg": "ES256", "kid": keyID, "typ": "JWT"]) + "." + encode(claims)
        let key = try P256.Signing.PrivateKey(pemRepresentation: String(contentsOf: keyURL, encoding: .utf8))
        return try content + "." + key.signature(for: Data(content.utf8)).rawRepresentation.base64URL
    }
}

extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

public final class AppleClient {
    public typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let token: () throws -> String
    private let transport: Transport
    private static let host = "api.appstoreconnect.apple.com"

    public init(token: @escaping () throws -> String, transport: Transport? = nil) {
        self.token = token
        self.transport = transport ?? { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw ReleaseError("Non-HTTP Apple response") }
            return (data, response)
        }
    }

    public func request(_ path: String, method: String = "GET", body: JSON? = nil) async throws -> JSON {
        guard let url = URL(string: path.hasPrefix("https:") ? path : "https://\(Self.host)\(path)"),
              url.scheme == "https", url.host == Self.host else { throw ReleaseError("Refusing non-Apple API URL") }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = method
        request.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await transport(request)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? JSON ?? [:]
        guard (200..<300).contains(response.statusCode) else {
            let errors = (object["errors"] as? [JSON] ?? []).map {
                [$0["code"], $0["detail"]].compactMap { $0 as? String }.joined(separator: ": ")
            }.joined(separator: "; ")
            throw ReleaseError("Apple HTTP \(response.statusCode): \(errors.isEmpty ? "request failed" : errors)")
        }
        return object
    }

    public func pages(_ path: String) async throws -> [JSON] {
        var next: String? = path
        var items: [JSON] = []
        var seen = Set<String>()
        while let path = next {
            guard seen.insert(path).inserted else { throw ReleaseError("Apple returned a pagination cycle") }
            let object = try await request(path)
            guard let data = object["data"] as? [JSON] else { throw ReleaseError("Apple list response missing data") }
            items += data
            next = (object["links"] as? JSON)?["next"] as? String
        }
        return items
    }

    public func app(id: String) async throws -> JSON {
        let object = try await request("/v1/apps/\(id)")
        guard let app = object["data"] as? JSON,
              (app["attributes"] as? JSON)?["bundleId"] as? String == "co.snapwell" else {
            throw ReleaseError("App ID does not identify Snapwell (co.snapwell)")
        }
        return app
    }

    public func builds(appID: String, platform: String) async throws -> [JSON] {
        var next: String? = "/v1/builds?filter[app]=\(appID)&filter[preReleaseVersion.platform]=\(platform)&include=preReleaseVersion&limit=200"
        var builds: [JSON] = []
        var seen = Set<String>()
        while let path = next {
            guard seen.insert(path).inserted else { throw ReleaseError("Apple returned a pagination cycle") }
            let page = try await request(path)
            let included = page["included"] as? [JSON] ?? []
            guard let data = page["data"] as? [JSON] else { throw ReleaseError("Apple build response missing data") }
            for var build in data {
                let relationships = build["relationships"] as? JSON
                let relation = (relationships?["preReleaseVersion"] as? JSON)?["data"] as? JSON
                let version = included.first { $0["id"] as? String == relation?["id"] as? String && $0["type"] as? String == "preReleaseVersions" }
                var attributes = build["attributes"] as? JSON ?? [:]
                attributes["snapwellMarketingVersion"] = (version?["attributes"] as? JSON)?["version"]
                build["attributes"] = attributes
                builds.append(build)
            }
            next = (page["links"] as? JSON)?["next"] as? String
        }
        return builds
    }

    public func versions(appID: String, platform: String) async throws -> [JSON] {
        try await pages("/v1/apps/\(appID)/appStoreVersions?filter[platform]=\(platform)&include=build&limit=200")
    }

    public func prepareVersion(appID: String, platform: String, version: String, notes: String, locale: String) async throws -> JSON {
        let versions = try await versions(appID: appID, platform: platform)
        let existing = versions.first { ($0["attributes"] as? JSON)?["versionString"] as? String == version }
        var item: JSON
        if let existing { item = existing }
        else {
            let response = try await request("/v1/appStoreVersions", method: "POST", body: ["data": [
                "type": "appStoreVersions", "attributes": ["platform": platform, "versionString": version, "releaseType": "AFTER_APPROVAL"],
                "relationships": ["app": ["data": ["type": "apps", "id": appID]]]
            ]])
            guard let created = response["data"] as? JSON else { throw ReleaseError("Missing created version") }
            item = created
        }
        let id = try requiredID(item)
        let state = (item["attributes"] as? JSON)?["appVersionState"] as? String
            ?? (item["attributes"] as? JSON)?["appStoreState"] as? String ?? "UNKNOWN"
        guard ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "READY_FOR_REVIEW"].contains(state) else {
            throw ReleaseError("Version \(version) is not editable: \(state). Check release status before resuming.")
        }
        _ = try await request("/v1/appStoreVersions/\(id)", method: "PATCH", body: ["data": [
            "id": id, "type": "appStoreVersions", "attributes": ["releaseType": "AFTER_APPROVAL"]]])
        let localizations = try await pages("/v1/appStoreVersions/\(id)/appStoreVersionLocalizations?limit=200")
        guard let localization = localizations.first(where: { ($0["attributes"] as? JSON)?["locale"] as? String == locale }) else {
            throw ReleaseError("Version has no \(locale) localization; configure the locale in App Store Connect first")
        }
        _ = try await request("/v1/appStoreVersionLocalizations/\(try requiredID(localization))", method: "PATCH", body: ["data": [
            "id": try requiredID(localization), "type": "appStoreVersionLocalizations", "attributes": ["whatsNew": notes]]])
        return item
    }

    public func attach(versionID: String, buildID: String) async throws {
        _ = try await request("/v1/appStoreVersions/\(versionID)/relationships/build", method: "PATCH", body: [
            "data": ["type": "builds", "id": buildID]])
    }

    public func submit(appID: String, platform: String, versionID: String, resumeID: String? = nil, checkpoint: (String) throws -> Void = { _ in }) async throws -> JSON {
        let submissions = try await pages("/v1/reviewSubmissions?filter[app]=\(appID)&filter[platform]=\(platform)&limit=200")
        for submission in submissions {
            let id = try requiredID(submission)
            let state = (submission["attributes"] as? JSON)?["state"] as? String ?? "UNKNOWN"
            guard ["READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES", "COMPLETING", "CANCELING"].contains(state) else { continue }
            let items = try await pages("/v1/reviewSubmissions/\(id)/items?include=appStoreVersion&limit=200")
            let containsVersion = items.contains {
                let relationships = $0["relationships"] as? JSON
                return ((relationships?["appStoreVersion"] as? JSON)?["data"] as? JSON)?["id"] as? String == versionID
            }
            if containsVersion {
                try checkpoint(id)
                if ["WAITING_FOR_REVIEW", "IN_REVIEW", "COMPLETING"].contains(state) { return submission }
                guard state == "READY_FOR_REVIEW" else { throw ReleaseError("Review needs attention: \(state)") }
                guard items.count == 1 else { throw ReleaseError("Review contains other items; inspect before submitting") }
                return try await submitID(id)
            }
            if items.isEmpty && state == "READY_FOR_REVIEW" && id == resumeID {
                try checkpoint(id)
                try await addItem(submissionID: id, versionID: versionID)
                return try await submitID(id)
            }
            throw ReleaseError("Another active review submission exists for this platform; resolve it before submitting")
        }
        let response = try await request("/v1/reviewSubmissions", method: "POST", body: ["data": [
            "type": "reviewSubmissions", "attributes": ["platform": platform],
            "relationships": ["app": ["data": ["type": "apps", "id": appID]]]]])
        guard let submission = response["data"] as? JSON else { throw ReleaseError("Missing review submission") }
        let id = try requiredID(submission)
        try checkpoint(id)
        try await addItem(submissionID: id, versionID: versionID)
        return try await submitID(id)
    }

    private func addItem(submissionID id: String, versionID: String) async throws {
        _ = try await request("/v1/reviewSubmissionItems", method: "POST", body: ["data": [
            "type": "reviewSubmissionItems", "relationships": [
                "reviewSubmission": ["data": ["type": "reviewSubmissions", "id": id]],
                "appStoreVersion": ["data": ["type": "appStoreVersions", "id": versionID]]]]])
    }

    private func submitID(_ id: String) async throws -> JSON {
        let response = try await request("/v1/reviewSubmissions/\(id)", method: "PATCH", body: ["data": [
            "type": "reviewSubmissions", "id": id, "attributes": ["submitted": true]]])
        guard let data = response["data"] as? JSON else { throw ReleaseError("Missing submitted review state") }
        return data
    }
}

public func requiredID(_ object: JSON) throws -> String {
    guard let id = object["id"] as? String, !id.isEmpty else { throw ReleaseError("Apple response missing resource ID") }
    return id
}

public func validateNotes(_ notes: String) throws {
    let lines = notes.split(whereSeparator: \.isNewline).map(String.init)
    guard (2...4).contains(lines.count), lines.allSatisfy({ $0.hasPrefix("• ") && $0.count > 4 }),
          notes.count <= 4000 else { throw ReleaseError("What's New must contain 2–4 nonempty • bullets and at most 4,000 characters") }
}

public func nextBuild(_ builds: [JSON], local: Int) throws -> Int {
    let numbers = try builds.map { build -> Int in
        guard let value = (build["attributes"] as? JSON)?["version"] as? String, let number = Int(value) else {
            throw ReleaseError("Non-integer remote build number; choose the next build explicitly")
        }
        return number
    }
    guard let highest = ([local] + numbers).max(), highest < Int.max else { throw ReleaseError("Invalid build number") }
    return highest + 1
}
