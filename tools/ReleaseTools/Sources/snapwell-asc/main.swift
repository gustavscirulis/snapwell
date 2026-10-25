import Foundation
import ReleaseCore

@main struct Main {
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            guard let command = args.first else { throw ReleaseError("Expected inspect, stage, submit, or status") }
            var options: [String: String] = [:]
            var index = 1
            while index < args.count {
                guard args[index].hasPrefix("--"), index + 1 < args.count else { throw ReleaseError("Invalid arguments") }
                options[String(args[index].dropFirst(2))] = args[index + 1]
                index += 2
            }
            let appID = ProcessInfo.processInfo.environment["ASC_APP_ID"] ?? "6762541353"
            guard appID.allSatisfy(\.isNumber) else { throw ReleaseError("Invalid ASC_APP_ID") }
            guard let platform = options["platform"], ["macos", "ios"].contains(platform) else {
                throw ReleaseError("--platform must be macos or ios")
            }
            let apiPlatform = platform == "macos" ? "MAC_OS" : "IOS"
            let credentials = try Credentials()
            let client = AppleClient(token: { try credentials.token() })
            let app = try await client.app(id: appID)
            var output: JSON = ["app_id": appID, "platform": platform,
                                "primary_locale": (app["attributes"] as? JSON)?["primaryLocale"] as? String ?? "en-US"]
            switch command {
            case "inspect", "status":
                let builds = try await client.builds(appID: appID, platform: apiPlatform)
                output["builds"] = builds
                output["versions"] = try await client.versions(appID: appID, platform: apiPlatform)
                if command == "inspect" {
                    output["next_build"] = try nextBuild(builds, local: Int(options["local-build"] ?? "0") ?? 0)
                }
            case "stage":
                guard let version = options["version"], let buildID = options["build-id"],
                      let path = options["notes"] else { throw ReleaseError("stage needs --version, --build-id, --notes") }
                let notes = try String(contentsOfFile: path, encoding: .utf8)
                try validateNotes(notes)
                let versionObject = try await client.prepareVersion(appID: appID, platform: apiPlatform, version: version,
                    notes: notes, locale: options["locale"] ?? "en-US")
                let versionID = try requiredID(versionObject)
                try await client.attach(versionID: versionID, buildID: buildID)
                output["version_id"] = versionID
            case "submit":
                guard let id = options["version-id"] else { throw ReleaseError("submit needs --version-id") }
                guard let checkpoint = options["checkpoint"] else { throw ReleaseError("submit needs --checkpoint for resumable submission") }
                let url = URL(fileURLWithPath: checkpoint)
                let saved = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? JSON }
                if let saved, saved["version_id"] as? String != id { throw ReleaseError("Submission checkpoint version mismatch") }
                output["submission"] = try await client.submit(appID: appID, platform: apiPlatform, versionID: id,
                    resumeID: saved?["submission_id"] as? String, checkpoint: { submissionID in
                        let data = try JSONSerialization.data(withJSONObject: ["version_id": id, "submission_id": submissionID], options: [.sortedKeys])
                        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try data.write(to: url, options: .atomic)
                    })
            default: throw ReleaseError("Unknown command: \(command)")
            }
            let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
