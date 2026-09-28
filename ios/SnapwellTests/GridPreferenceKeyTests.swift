import Testing
import SwiftUI
@testable import Snapwell

@Suite("Detail transition geometry", .tags(.layout))
@MainActor
struct DetailTransitionGeometryTests {
    @Test("Opening and closing frames use the measured overlay viewport")
    func overlayCoordinates() {
        let viewport = CGRect(x: 12, y: 59, width: 393, height: 759)
        let source = CGRect(x: 32, y: 180, width: 170, height: 220)
        let destination = CGRect(x: 215, y: 510, width: 170, height: 180)

        #expect(DetailOverlayGeometry.localFrame(source, in: viewport) == CGRect(x: 20, y: 121, width: 170, height: 220))
        #expect(DetailOverlayGeometry.localFrame(destination, in: viewport) == CGRect(x: 203, y: 451, width: 170, height: 180))
        #expect(DetailOverlayGeometry.localFrame(destination, in: viewport.offsetBy(dx: 0, dy: 11)) == CGRect(x: 203, y: 440, width: 170, height: 180))
        #expect(DetailOverlayGeometry.localTopInset(115, in: viewport) == 56)
    }

    @Test("Closing hero starts at the dragged and scaled media frame")
    func displayedMediaFrame() {
        let media = CGRect(x: 20, y: 100, width: 360, height: 500)
        let viewport = CGSize(width: 400, height: 800)

        #expect(DetailOverlayGeometry.displayedMediaFrame(
            media, in: viewport, scrollOffset: 0, dragOffset: 120,
            scale: 0.9, swipeOffset: 0
        ) == CGRect(x: 38, y: 250, width: 324, height: 450))

        #expect(DetailOverlayGeometry.displayedMediaFrame(
            media, in: viewport, scrollOffset: 80, dragOffset: 0,
            scale: 1, swipeOffset: 12
        ) == CGRect(x: 32, y: 20, width: 360, height: 500))

        #expect(DetailOverlayGeometry.displayedMediaFrame(
            media, in: viewport, scrollOffset: -20, dragOffset: 120,
            scale: 0.9, swipeOffset: 0
        ) == CGRect(x: 38, y: 268, width: 324, height: 450))
    }

    @Test("Close target needs at least half the cell visible")
    func targetVisibility() {
        let viewport = CGRect(x: 0, y: 0, width: 300, height: 400)
        let mostlyVisible = CGRect(x: 20, y: 350, width: 100, height: 100)
        let mostlyHidden = CGRect(x: 20, y: 351, width: 100, height: 100)
        #expect(DetailGridTarget.visible(itemID: "a", host: .all, frame: mostlyVisible, viewport: viewport) != nil)
        #expect(DetailGridTarget.visible(itemID: "a", host: .all, frame: mostlyHidden, viewport: viewport) == nil)
        #expect(DetailGridTarget.visible(itemID: "a", host: .all, frame: .zero, viewport: viewport) == nil)
    }

    @Test("Close target records its grid host")
    func targetHost() {
        let frame = CGRect(x: 10, y: 10, width: 100, height: 100)
        let target = DetailGridTarget.visible(itemID: "a", host: .space("one"), frame: frame, viewport: frame)
        #expect(target?.host == .space("one"))
        #expect(target?.itemID == "a")
    }

    @Test("Hero crop covers the taller endpoint with one top slice")
    func heroCrop() {
        let basis = DetailHeroCrop.tallestBox(
            CGSize(width: 100, height: 200), CGSize(width: 300, height: 300)
        )
        #expect(basis == CGSize(width: 100, height: 200))
        #expect(DetailHeroCrop.sliceHeight(pixelWidth: 800, pixelHeight: 4000, covering: basis) == 1600)
        #expect(DetailHeroCrop.sliceHeight(pixelWidth: 800, pixelHeight: 1000, covering: basis) == nil)
    }
}

@Suite("DetailChrome", .tags(.layout))
@MainActor
struct DetailChromeTests {

    @Test("Toolbar title prefers current item summary and falls back when missing")
    func toolbarTitlePrefersSummary() {
        let summarized = MediaItem(mediaType: .image, filename: "a.jpg", width: 100, height: 100)
        summarized.analysisResult = AnalysisResult(
            imageContext: "Context",
            imageSummary: "Hero Shot",
            patterns: [],
            provider: "test",
            model: "test"
        )

        let untitled = MediaItem(mediaType: .image, filename: "b.jpg", width: 100, height: 100)

        #expect(
            DetailChrome.toolbarTitle(
                currentItemId: summarized.id,
                items: [summarized, untitled],
                fallback: "All media"
            ) == "Hero Shot"
        )

        #expect(
            DetailChrome.toolbarTitle(
                currentItemId: untitled.id,
                items: [summarized, untitled],
                fallback: "All media"
            ) == "All media"
        )
    }

    @Test("Detail mode hides top actions and tab bar")
    func detailModeVisibilityRules() {
        #expect(DetailChrome.showsTopBarActions(isDetailPresented: false))
        #expect(!DetailChrome.showsTopBarActions(isDetailPresented: true))
        #expect(!DetailChrome.hidesTabBar(isDetailPresented: false))
        #expect(DetailChrome.hidesTabBar(isDetailPresented: true))
    }

    @Test("Reserved top inset includes safe area and toolbar spacing")
    func reservedTopInsetAddsToolbarClearance() {
        let inset = DetailChrome.reservedTopInset(safeAreaTop: 59)
        #expect(inset == 59 + DetailChrome.navigationBarHeight + DetailChrome.mediaTopPadding)
    }
}
