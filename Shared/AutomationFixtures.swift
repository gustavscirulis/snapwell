#if SNAPWELL_AUTOMATION
import Foundation
import SwiftData
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum AutomationFixtures {
    @MainActor static func prepare() throws {
        let domain = Bundle.main.bundleIdentifier!
        precondition(domain == "co.snapwell.automation")
        UserDefaults.standard.removePersistentDomain(forName: domain)
        if AutomationEnvironment.argument("--snapwell-fixture") != nil {
            UserDefaults.standard.set("openai", forKey: "aiProvider")
            UserDefaults.standard.set(AIProvider.openai.defaultModel, forKey: "openaiModel")
            try KeychainService.set(key: "automation-only", forService: AIProvider.openai.keychainService)
            #if !os(macOS)
            try KeySyncService.shared.saveAPIKey("automation-only", for: .openai, rootURL: nil)
            #endif
        }
        let root = AutomationEnvironment.rootURL
        let incoming = root.appendingPathComponent("incoming/sample.png")
        let orange = try imageData(red: 255, green: 149, blue: 0)
        try orange.png.write(to: incoming, options: .atomic)
        if let video = Bundle.main.url(forResource: "clip", withExtension: "mp4") {
            let destination = root.appendingPathComponent("incoming/clip.mp4")
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: video, to: destination)
            }
        } else { throw CocoaError(.fileNoSuchFile) }
        guard AutomationEnvironment.argument("--snapwell-fixture") == "library" else { return }
        let blue = try imageData(red: 0, green: 122, blue: 255)
        for (id, summary, image) in [("fixture-orange", "Orange inspiration", orange),
                                     ("fixture-blue", "Blue architecture", blue)] {
            try image.png.write(to: root.appendingPathComponent("images/\(id).png"), options: .atomic)
            try image.jpeg.write(to: root.appendingPathComponent("thumbnails/\(id).jpg"), options: .atomic)
            let sidecar: [String: Any] = [
                "id": id, "type": "image", "width": 320, "height": 240,
                "createdAt": "2026-01-01T12:00:00Z", "analyzedAt": "2026-01-01T12:00:00Z",
                "spaceIds": ["fixture-space"], "imageSummary": summary,
                "imageContext": summary, "patterns": [["name": "Fixture", "confidence": 1.0]]
            ]
            try JSONSerialization.data(withJSONObject: sidecar, options: [.sortedKeys])
                .write(to: root.appendingPathComponent("metadata/\(id).json"), options: .atomic)
        }
        let spaces: [String: Any] = ["useAllSpaceGuidance": false, "spaces": [[
            "id": "fixture-space", "name": "Inspiration", "order": 0,
            "createdAt": "2026-01-01T12:00:00Z", "useCustomPrompt": false
        ]]]
        try JSONSerialization.data(withJSONObject: spaces, options: [.sortedKeys])
            .write(to: root.appendingPathComponent("spaces.json"), options: .atomic)
    }

    static func imageData(red: UInt8, green: UInt8, blue: UInt8) throws -> (png: Data, jpeg: Data) {
        let width = 320
        let height = 240
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = red
            pixels[offset + 1] = green
            pixels[offset + 2] = blue
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw CocoaError(.fileWriteUnknown) }

        func encode(_ type: UTType) throws -> Data {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)
            else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
            return data as Data
        }
        return (try encode(.png), try encode(.jpeg))
    }

    static func analysis(provider: String, model: String) -> AnalysisResult {
        AnalysisResult(imageContext: "Orange inspiration fixture", imageSummary: "Orange inspiration",
                       patterns: [PatternTag(name: "Fixture", confidence: 1)],
                       analyzedAt: Date(timeIntervalSince1970: 1_767_268_800), provider: provider, model: model)
    }
}
#endif
