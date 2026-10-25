import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import Snapwell

private final class FixtureBundleMarker {}

@Suite("Shared sidecar compatibility")
struct SharedSidecarTests {
    @Test func bothPlatformsReadAndPreserveTheSameSidecar() throws {
        let url = try #require(Bundle(for: FixtureBundleMarker.self).url(forResource: "sidecar", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(SidecarMetadata.self, from: data)
        #expect(metadata.id == "shared-video")
        #expect(metadata.type == "video")
        #expect(metadata.duration == 1)
        #expect(metadata.normalizedSpaceIDs == ["inspiration", "work"])
        #expect(metadata.patterns?.first?.confidence == 0.9)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let actual = try #require(JSONSerialization.jsonObject(with: encoder.encode(metadata)) as? NSDictionary)
        let expected = try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
        #expect(actual == expected)
    }

    @Test func bothPlatformsPreserveSpacesAndGuidance() throws {
        let url = try #require(Bundle(for: FixtureBundleMarker.self).url(forResource: "spaces", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(SidecarSpacesFile.self, from: data)
        #expect(file.spaces.first?.id == "inspiration")
        #expect(file.spaces.first?.hideFromAllMedia == true)
        #expect(file.spaces.first?.useCustomPrompt == true)
        #expect(file.useAllSpaceGuidance)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let actual = try #require(JSONSerialization.jsonObject(with: encoder.encode(file)) as? NSDictionary)
        let expected = try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
        #expect(actual == expected)
    }

    @Test func hostedTestsUseIsolatedStorageAndCredentials() throws {
        #expect(AutomationEnvironment.isEnabled)
        #expect(!AutomationEnvironment.usesFixtureProviders)
        #expect(Bundle.main.bundleIdentifier == "co.snapwell.automation")
        #expect(AutomationEnvironment.rootURL.pathComponents.contains("SnapwellAutomation"))
        let service = "isolation-" + UUID().uuidString
        try KeychainService.set(key: "test-only", forService: service)
        #expect(AutomationEnvironment.key(service) == "test-only")
        try KeychainService.delete(service: service)
        #expect(try KeychainService.get(service: service) == nil)
    }

    @Test func uiFixturesHaveOpaqueColoredMediaAndJPEGThumbnails() throws {
        for (red, green, blue) in [(UInt8(255), UInt8(149), UInt8(0)), (UInt8(0), UInt8(122), UInt8(255))] {
            let fixture = try AutomationFixtures.imageData(red: red, green: green, blue: blue)
            for (data, type) in [(fixture.png, UTType.png), (fixture.jpeg, UTType.jpeg)] {
                let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
                #expect(CGImageSourceGetType(source) as String? == type.identifier)
                let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
                #expect(image.width == 320)
                #expect(image.height == 240)
                var pixel = [UInt8](repeating: 0, count: 4)
                let drawn = pixel.withUnsafeMutableBytes { bytes in
                    guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1,
                                                  bitsPerComponent: 8, bytesPerRow: 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
                    else { return false }
                    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                    return true
                }
                #expect(drawn)
                #expect(pixel[3] == 255)
                #expect(abs(Int(pixel[0]) - Int(red)) <= 4)
                #expect(abs(Int(pixel[1]) - Int(green)) <= 4)
                #expect(abs(Int(pixel[2]) - Int(blue)) <= 4)
            }
        }
    }

}
