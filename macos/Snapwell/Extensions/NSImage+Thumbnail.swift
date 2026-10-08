import AppKit

extension NSImage {
    /// Resize image to fit within maxWidth preserving aspect ratio, export as JPEG data
    func thumbnailData(maxWidth: CGFloat = 800, quality: CGFloat = 0.9) -> Data? {
        guard maxWidth.isFinite, maxWidth >= 1,
              let source = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let originalWidth = CGFloat(source.width)
        let originalHeight = CGFloat(source.height)

        guard originalWidth > 0, originalHeight > 0 else { return nil }

        let scale = min(1, maxWidth / originalWidth)
        let width = max(1, Int((originalWidth * scale).rounded(.down)))
        let height = max(1, Int((originalHeight * scale).rounded()))

        // lockFocus rounds a fractional point-sized canvas up to backing pixels.
        // Its unused top/right pixels become white when encoded as JPEG. Render
        // directly into an integer-sized bitmap, independent of screen density.
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else {
            return nil
        }

        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.interpolationQuality = .high
        context.draw(source, in: bounds)
        guard let resized = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: resized)
            .representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// Remove the spare backing pixel from thumbnails written by the old
    /// lockFocus renderer. This only applies to cached thumbnails, never originals.
    func removingThumbnailFocusPadding() -> NSImage {
        guard size.width > 0, size.width <= 800, size.height > 0,
              let source = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return self }

        let density = CGFloat(source.width) / size.width
        let backingScale = density.rounded()
        guard backingScale >= 1, backingScale <= 3,
              abs(density - backingScale) < 0.01 else { return self }

        let width = Int((size.width * backingScale).rounded())
        let height = Int((size.height * backingScale).rounded())
        let extraWidth = source.width - width
        let extraHeight = source.height - height
        guard width > 0, height > 0,
              (0...1).contains(extraWidth), (0...1).contains(extraHeight),
              extraWidth + extraHeight > 0,
              let cropped = source.cropping(to: CGRect(
                x: 0, y: extraHeight, width: width, height: height
              )) else { return self }

        return NSImage(cgImage: cropped, size: size)
    }

    /// Get pixel dimensions
    var pixelSize: NSSize? {
        guard let rep = self.representations.first else { return nil }
        return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }
}
