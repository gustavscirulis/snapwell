import Testing
import AppKit
import CoreGraphics
@testable import Snapwell

@Suite("TopCroppedImage fill sizing", .tags(.layout))
struct TopCroppedImageTests {

    @Test("Tall image overflows vertically so the top stays visible")
    func tallImageIsWidthDriven() {
        // 1000x20000 screenshot in a 1:2-clamped grid cell.
        let result = TopCroppedImage.fillSize(
            for: CGSize(width: 1000, height: 20000),
            in: CGSize(width: 400, height: 800)
        )

        #expect(result.width == 400)
        #expect(result.height == 8000)
    }

    @Test("Wide image overflows horizontally")
    func wideImageIsHeightDriven() {
        let result = TopCroppedImage.fillSize(
            for: CGSize(width: 4000, height: 1000),
            in: CGSize(width: 400, height: 400)
        )

        #expect(result.width == 1600)
        #expect(result.height == 400)
    }

    @Test("Matching aspect ratio fills exactly with no crop or distortion")
    func matchingAspectFillsExactly() {
        let result = TopCroppedImage.fillSize(
            for: CGSize(width: 1600, height: 900),
            in: CGSize(width: 800, height: 450)
        )

        #expect(result.width == 800)
        #expect(result.height == 450)
    }

    @Test("Result never leaves a gap on either axis")
    func neverUnderfills() {
        let box = CGSize(width: 320, height: 640)
        let sources = [
            CGSize(width: 100, height: 100),
            CGSize(width: 3000, height: 40),
            CGSize(width: 40, height: 3000),
            CGSize(width: 320, height: 640)
        ]

        for source in sources {
            let result = TopCroppedImage.fillSize(for: source, in: box)
            #expect(result.width >= box.width)
            #expect(result.height >= box.height)
        }
    }

    @Test("Tall image draw rect starts at the top edge")
    func tallImageDrawRectIsTopAligned() {
        let box = CGSize(width: 400, height: 800)
        let result = TopCroppedImage.drawRect(
            for: CGSize(width: 1000, height: 20000),
            in: box
        )

        #expect(result.minX == 0)
        #expect(result.minY == 0)
        #expect(result.width == box.width)
        #expect(result.height == 8000)
    }

    @Test("Wide image draw rect stays horizontally centered")
    func wideImageDrawRectIsCentered() {
        let result = TopCroppedImage.drawRect(
            for: CGSize(width: 4000, height: 1000),
            in: CGSize(width: 400, height: 400)
        )

        #expect(result.minX == -600)
        #expect(result.minY == 0)
        #expect(result.width == 1600)
        #expect(result.height == 400)
    }

    @Test("Draw rect always covers the clipping box")
    func drawRectAlwaysCoversBox() {
        let box = CGSize(width: 320, height: 640)
        let sources = [
            CGSize(width: 100, height: 100),
            CGSize(width: 3000, height: 40),
            CGSize(width: 40, height: 3000),
            CGSize(width: 320, height: 640)
        ]

        for source in sources {
            let result = TopCroppedImage.drawRect(for: source, in: box)
            #expect(result.minX <= 0)
            #expect(result.minY == 0)
            #expect(result.maxX >= box.width)
            #expect(result.maxY >= box.height)
        }
    }

    @Test("Hero uses one stable slice while its mask changes aspect ratio")
    func heroCropStaysStable() {
        let thumbnail = CGSize(width: 400, height: 800)
        let viewer = CGSize(width: 800, height: 820)
        let cropBasis = TopCroppedImage.tallestBox(thumbnail, viewer)

        #expect(cropBasis == thumbnail)

        // An 800px-wide source is cropped once to the thumbnail's 1:2 aspect. Both endpoint
        // draw sizes preserve that ratio, so only the outer mask changes shape during flight.
        let croppedSource = CGSize(width: 800, height: 1600)
        #expect(TopCroppedImage.fillSize(for: croppedSource, in: thumbnail) == thumbnail)
        #expect(
            TopCroppedImage.fillSize(for: croppedSource, in: viewer)
                == CGSize(width: 800, height: 1600)
        )
    }

    @Test("Hero crop basis ignores invalid boxes")
    func heroCropBasisIgnoresInvalidBoxes() {
        let valid = CGSize(width: 300, height: 900)

        #expect(TopCroppedImage.tallestBox(.zero, valid) == valid)
        #expect(TopCroppedImage.tallestBox(.zero, CGSize(width: 100, height: 0)) == .zero)
    }

    @Test("Tall thumbnail is trimmed to just the rows the box can show")
    func tallThumbnailIsTrimmed() {
        // 800x9302 is what NSImage.thumbnailData produces for a full-page screenshot.
        let slice = TopCroppedImage.sliceHeight(
            pixelWidth: 800,
            pixelHeight: 9302,
            covering: CGSize(width: 1200, height: 900)
        )

        #expect(slice == 600)
    }

    @Test("Tall thumbnail crop retains the source's top pixels")
    func tallThumbnailCropRetainsTopPixels() throws {
        let source = try stripedImage(
            width: 2,
            height: 4,
            topColor: [255, 0, 0, 255],
            bottomColor: [0, 0, 255, 255]
        )

        let result = TopCroppedImage.topSlice(
            of: source,
            covering: CGSize(width: 2, height: 2)
        )
        let cropped = try #require(
            result.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        let rep = NSBitmapImageRep(cgImage: cropped)

        #expect(cropped.width == 2)
        #expect(cropped.height == 2)
        for x in 0..<cropped.width {
            for y in 0..<cropped.height {
                let color = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                #expect(color.redComponent > 0.9)
                #expect(color.blueComponent < 0.1)
            }
        }
    }

    @Test("Trimmed slice still fully covers the box after scaling")
    func trimmedSliceStillCoversBox() {
        // Ratios that don't divide evenly, to catch a rounding-down gap at the bottom.
        let boxes = [
            CGSize(width: 301, height: 907),
            CGSize(width: 1193, height: 733),
            CGSize(width: 77, height: 1000)
        ]

        for box in boxes {
            guard let slice = TopCroppedImage.sliceHeight(
                pixelWidth: 803,
                pixelHeight: 9302,
                covering: box
            ) else { continue }

            let drawn = TopCroppedImage.fillSize(
                for: CGSize(width: 803, height: slice),
                in: box
            )
            #expect(drawn.height >= box.height)
            #expect(drawn.width >= box.width)
        }
    }

    @Test("Images that already fit are left alone")
    func shortImagesAreNotTrimmed() {
        // Box is taller than the image can fill — nothing to trim.
        #expect(TopCroppedImage.sliceHeight(
            pixelWidth: 800, pixelHeight: 600, covering: CGSize(width: 400, height: 800)
        ) == nil)

        // Exact aspect match.
        #expect(TopCroppedImage.sliceHeight(
            pixelWidth: 800, pixelHeight: 400, covering: CGSize(width: 1200, height: 600)
        ) == nil)

        // Wide image in a square box.
        #expect(TopCroppedImage.sliceHeight(
            pixelWidth: 4000, pixelHeight: 1000, covering: CGSize(width: 400, height: 400)
        ) == nil)
    }

    @Test("Degenerate slice inputs return nil instead of producing NaN")
    func degenerateSliceInputs() {
        let box = CGSize(width: 200, height: 400)

        #expect(TopCroppedImage.sliceHeight(pixelWidth: 0, pixelHeight: 100, covering: box) == nil)
        #expect(TopCroppedImage.sliceHeight(pixelWidth: 100, pixelHeight: 0, covering: box) == nil)
        #expect(TopCroppedImage.sliceHeight(
            pixelWidth: 100, pixelHeight: 9000, covering: .zero
        ) == nil)
    }

    @Test("Degenerate sizes fall back to the box instead of producing NaN")
    func degenerateSizesFallBack() {
        let box = CGSize(width: 200, height: 400)

        #expect(TopCroppedImage.fillSize(for: .zero, in: box) == box)
        #expect(TopCroppedImage.fillSize(for: CGSize(width: 100, height: 0), in: box) == box)
        #expect(TopCroppedImage.fillSize(for: CGSize(width: 0, height: 100), in: box) == box)
        #expect(
            TopCroppedImage.fillSize(for: CGSize(width: 100, height: 100), in: .zero) == .zero
        )
    }

    private func stripedImage(
        width: Int,
        height: Int,
        topColor: [UInt8],
        bottomColor: [UInt8]
    ) throws -> NSImage {
        #expect(topColor.count == 4)
        #expect(bottomColor.count == 4)

        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * height * 4)
        for y in 0..<height {
            let color = y < height / 2 ? topColor : bottomColor
            for _ in 0..<width {
                pixels.append(contentsOf: color)
            }
        }

        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
        let cgImage = try #require(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}
