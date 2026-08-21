import SwiftUI

/// Drop-in replacement for `.resizable().aspectRatio(contentMode: .fill).frame(...).clipped()`
/// that anchors the crop to the top instead of SwiftUI's default center.
///
/// Matters for very tall media: the grid clamps cell height at 1:2 (`MediaItem.gridAspectRatio`)
/// and the detail hero clamps to the window height, so a long screenshot overflows its box by a
/// lot. Center-cropping it shows a meaningless middle slice, and — because the settled detail
/// ScrollView renders the image at its full height starting from the top — the hero appeared to
/// jump when it handed off. Mirrors the iOS pattern in `Views/Grid/GridItemView.swift`.
struct TopCroppedImage: View {
    let image: NSImage
    let size: CGSize
    /// Optional fixed crop basis for animated uses. Keeping this stable while `size` changes
    /// prevents SwiftUI from morphing between bitmap slices with different aspect ratios.
    let cropBasis: CGSize?

    init(image: NSImage, size: CGSize, cropBasis: CGSize? = nil) {
        self.image = image
        self.size = size
        self.cropBasis = cropBasis
    }

    var body: some View {
        let source = Self.topSlice(of: image, covering: cropBasis ?? size)
        let drawRect = Self.drawRect(for: source.size, in: size)

        Color.clear
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .topLeading) {
                Image(nsImage: source)
                    .resizable()
                    .frame(width: drawRect.width, height: drawRect.height)
                    .offset(x: drawRect.minX, y: drawRect.minY)
                    // Clipping only affects drawing. Keep the overflowing image out of hit
                    // testing so it cannot cover neighboring masonry cells.
                    .allowsHitTesting(false)
            }
            .clipped()
            .contentShape(.interaction, Rectangle())
    }

    /// Returns the box with the greatest height-to-width ratio.
    ///
    /// A slice large enough to cover this box can also cover every aspect ratio between the
    /// supplied endpoints. Hero animations use it to crop once for the whole flight: the image
    /// then grows at one uniform scale while the outer frame acts as a top-anchored reveal mask.
    nonisolated static func tallestBox(_ boxes: CGSize...) -> CGSize {
        boxes
            .filter { $0.width > 0 && $0.height > 0 }
            .max { lhs, rhs in
                lhs.height / lhs.width < rhs.height / rhs.width
            } ?? .zero
    }

    /// Size the image must be drawn at to cover `box` without distortion.
    ///
    /// Scales by whichever axis needs the most, so the result is never smaller than `box` on
    /// either side — identical to `contentMode: .fill`, just expressed as an explicit size so
    /// the overflow can be anchored.
    nonisolated static func fillSize(for imageSize: CGSize, in box: CGSize) -> CGSize {
        // NSImage.size is DPI-aware, but DPI scales both axes equally so the ratio holds.
        guard imageSize.width > 0, imageSize.height > 0,
              box.width > 0, box.height > 0 else { return box }

        let scale = max(box.width / imageSize.width, box.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// The scaled image's placement inside its fixed clipping box.
    ///
    /// Vertical overflow always starts at the box's top edge. Horizontal overflow remains
    /// centered, matching aspect-fill behavior for wide images without exposing the oversized
    /// image's bounds to layout or hit testing.
    nonisolated static func drawRect(for imageSize: CGSize, in box: CGSize) -> CGRect {
        let drawSize = fillSize(for: imageSize, in: box)
        return CGRect(
            x: (box.width - drawSize.width) / 2,
            y: 0,
            width: drawSize.width,
            height: drawSize.height
        )
    }

    /// Trims a very tall image to just the top region `box` can actually show, returning the
    /// original when nothing would be trimmed.
    ///
    /// Thumbnails are only width-limited (see `NSImage.thumbnailData`), so a full-page
    /// screenshot lands on disk as something like 800x9300. Drawing that scaled-to-fill and
    /// clipping it hands SwiftUI a layer many thousands of points tall — past Metal's texture
    /// limit — and the detail hero re-rasterizes it on every frame of the spring. Cropping
    /// first keeps the layer the size of the box. `CGImage.cropping(to:)` is a cheap view onto
    /// the same backing store, not a pixel copy, so this is safe to call from `body`.
    nonisolated static func topSlice(of image: NSImage, covering box: CGSize) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        let pixelWidth = CGFloat(cg.width)
        let pixelHeight = CGFloat(cg.height)

        guard let sliceHeight = sliceHeight(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            covering: box
        ) else { return image }

        // CGImage is top-down, so y == 0 is the top of the picture.
        guard let sliced = cg.cropping(
            to: CGRect(x: 0, y: 0, width: pixelWidth, height: sliceHeight)
        ) else { return image }

        return NSImage(cgImage: sliced, size: NSSize(width: pixelWidth, height: sliceHeight))
    }

    /// Pixel rows needed off the top to cover `box`, or nil when the image is already short
    /// enough that nothing would be trimmed.
    nonisolated static func sliceHeight(
        pixelWidth: CGFloat,
        pixelHeight: CGFloat,
        covering box: CGSize
    ) -> CGFloat? {
        guard pixelWidth > 0, pixelHeight > 0, box.width > 0, box.height > 0 else { return nil }

        // Round up so the slice can never come up a fraction of a pixel short of the box.
        let needed = (pixelWidth * box.height / box.width).rounded(.up)
        guard needed < pixelHeight else { return nil }
        return needed
    }
}
