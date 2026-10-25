import Testing
import Foundation
import CryptoKit
@testable import ReleaseCore

@Test func notesRequireRealBullets() throws {
    try validateNotes("• Smoother image transitions.\n• More reliable imports.\n")
    #expect(throws: ReleaseError.self) { try validateNotes("One improvement") }
    #expect(throws: ReleaseError.self) { try validateNotes("• \n• ") }
    #expect(throws: ReleaseError.self) { try validateNotes(Array(repeating: "• Item", count: 5).joined(separator: "\n")) }
}

@Test func buildNumbersIncludeRemoteAndLocal() throws {
    #expect(try nextBuild([["attributes": ["version": "19"]]], local: 14) == 20)
    #expect(try nextBuild([], local: 22) == 23)
    #expect(throws: ReleaseError.self) { try nextBuild([["attributes": ["version": "1.2"]]], local: 1) }
}

@Test func signsAppleJWTWithoutLeakingKey() throws {
    let key = P256.Signing.PrivateKey()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try key.pemRepresentation.write(to: url, atomically: true, encoding: .utf8)
    let credentials = try Credentials(environment: ["ASC_KEY_ID": "TEST", "ASC_KEY_PATH": url.path, "ASC_ISSUER_ID": "issuer"])
    let token = try credentials.token(now: Date(timeIntervalSince1970: 1000))
    let parts = token.split(separator: ".").map(String.init)
    #expect(parts.count == 3)
    func decode(_ string: String) -> Data {
        let base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4))!
    }
    let claims = try #require(JSONSerialization.jsonObject(with: decode(parts[1])) as? JSON)
    #expect(claims["iss"] as? String == "issuer")
    #expect(claims["exp"] as? Int == 1600)
    let signature = try P256.Signing.ECDSASignature(rawRepresentation: decode(parts[2]))
    #expect(key.publicKey.isValidSignature(signature, for: Data((parts[0] + "." + parts[1]).utf8)))
}

@Test func paginationAndAppleHostRestriction() async throws {
    var requests: [String] = []
    let client = AppleClient(token: { "test" }, transport: { request in
        requests.append(request.url!.absoluteString)
        let body: JSON = requests.count == 1
            ? ["data": [["id": "first"]], "links": ["next": "https://api.appstoreconnect.apple.com/v1/next"]]
            : ["data": [["id": "second"]]]
        return (try JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
    #expect(try await client.pages("/v1/start").count == 2)
    await #expect(throws: ReleaseError.self) { try await client.request("https://example.com/steal-token") }
    #expect(requests.count == 2)
}

@Test func appleErrorsAreFailures() async throws {
    let client = AppleClient(token: { "secret-not-logged" }, transport: { request in
        let body: JSON = ["errors": [["code": "FORBIDDEN", "detail": "Insufficient role"]]]
        return (try JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!)
    })
    do { _ = try await client.request("/v1/apps/1"); Issue.record("Expected Apple error") }
    catch { #expect(error.localizedDescription.contains("Insufficient role")); #expect(!error.localizedDescription.contains("secret-not-logged")) }
}

@Test func resumedSubmissionDoesNotSubmitTwice() async throws {
    var methods: [String] = []
    let client = AppleClient(token: { "test" }, transport: { request in
        methods.append(request.httpMethod!)
        let body: JSON = request.url!.path.hasSuffix("/items")
            ? ["data": [["id": "item", "relationships": ["appStoreVersion": ["data": ["id": "version"]]]]]]
            : ["data": [["id": "review", "attributes": ["state": "WAITING_FOR_REVIEW"]]]]
        return (try JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
    #expect(try await client.submit(appID: "1", platform: "IOS", versionID: "version")["id"] as? String == "review")
    #expect(methods == ["GET", "GET"])
}

@Test func resumesOnlyTheRecordedEmptyReviewDraft() async throws {
    var writes: [String] = []
    var saved: String?
    let client = AppleClient(token: { "test" }, transport: { request in
        let path = request.url!.path
        let body: JSON
        if request.httpMethod == "GET" {
            body = path.hasSuffix("/items") ? ["data": []] : ["data": [["id": "draft", "attributes": ["state": "READY_FOR_REVIEW"]]]]
        } else {
            writes.append(request.httpMethod! + " " + path)
            body = ["data": ["id": "draft", "attributes": ["state": "WAITING_FOR_REVIEW"]]]
        }
        return (try JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
    await #expect(throws: ReleaseError.self) { try await client.submit(appID: "1", platform: "IOS", versionID: "version") }
    #expect(writes.isEmpty)
    _ = try await client.submit(appID: "1", platform: "IOS", versionID: "version", resumeID: "draft", checkpoint: { saved = $0 })
    #expect(saved == "draft")
    #expect(writes == ["POST /v1/reviewSubmissionItems", "PATCH /v1/reviewSubmissions/draft"])
}

@Test func stageChangesOnlyReleasePolicyAndExactWhatsNew() async throws {
    var mutations: [JSON] = []
    let notes = "• Faster imports.\n• Better search.\n"
    let client = AppleClient(token: { "test" }, transport: { request in
        let body: JSON
        if request.httpMethod == "GET" {
            body = request.url!.path.hasSuffix("/appStoreVersionLocalizations")
                ? ["data": [["id": "english", "attributes": ["locale": "en-US"]]]]
                : ["data": [["id": "version", "attributes": ["versionString": "1.2.3", "appVersionState": "PREPARE_FOR_SUBMISSION"]]]]
        } else {
            mutations.append(try JSONSerialization.jsonObject(with: request.httpBody!) as! JSON)
            body = [:]
        }
        return (try JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
    _ = try await client.prepareVersion(appID: "1", platform: "MAC_OS", version: "1.2.3", notes: notes, locale: "en-US")
    #expect(mutations.count == 2)
    let policy = (mutations[0]["data"] as? JSON)?["attributes"] as? JSON
    let metadata = (mutations[1]["data"] as? JSON)?["attributes"] as? JSON
    #expect(policy?["releaseType"] as? String == "AFTER_APPROVAL")
    #expect(metadata?.count == 1)
    #expect(metadata?["whatsNew"] as? String == notes)
}

@Test func processedBuildKeepsItsMarketingVersion() async throws {
    let client = AppleClient(token: { "test" }, transport: { request in
        #expect(request.url!.absoluteString.contains("preReleaseVersion.platform"))
        let body: JSON = ["data": [["id": "build", "attributes": ["version": "12"], "relationships": ["preReleaseVersion": ["data": ["id": "pre"]]]]],
                          "included": [["id": "pre", "type": "preReleaseVersions", "attributes": ["version": "1.2.3"]]]]
        return (try JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
    let builds = try await client.builds(appID: "1", platform: "IOS")
    #expect((builds.first?["attributes"] as? JSON)?["snapwellMarketingVersion"] as? String == "1.2.3")
}
