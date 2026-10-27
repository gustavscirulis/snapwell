import XCTest

@MainActor
final class SnapwellUITests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "co.snapwell.automation")
    }

    @MainActor override func tearDown() async throws {
        #if os(macOS)
        let window = app.windows.firstMatch
        let screenshot = window.exists ? window.screenshot() : app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        #else
        let attachment = XCTAttachment(screenshot: app.screenshot())
        #endif
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if testRun?.hasSucceeded == false {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        app.terminate()
    }

    private func launch(_ fixture: String) {
        app.launchArguments = ["--snapwell-test-id", UUID().uuidString, "--snapwell-fixture", fixture]
        app.launch()
        XCTAssertTrue(app.staticTexts["automation-count"].waitForExistence(timeout: 30), "Library must mount")
    }

    private func media(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "media-" + id).firstMatch
    }

    private func waitForCount(_ count: Int) {
        waitForText(String(count), identifier: "automation-count")
    }

    private func waitForAnalysis(_ count: Int) {
        waitForText(String(count), identifier: "automation-analyzed")
    }

    private func waitForText(_ text: String, identifier: String) {
        let element = app.staticTexts[identifier]
        #if os(macOS)
        let predicate = NSPredicate(format: "value == %@", text)
        #else
        let predicate = NSPredicate(format: "label == %@", text)
        #endif
        let expected = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 30), .completed, "Expected \(identifier) to equal \(text)")
    }

    func testEmptyLibraryCanImportImage() {
        launch("empty")
        waitForCount(0)
        app.buttons["automation-import"].tap()
        waitForCount(1)
        waitForAnalysis(1)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'media-'")).firstMatch.waitForExistence(timeout: 10))
    }

    func testEmptyLibraryCanImportVideo() {
        launch("empty")
        waitForCount(0)
        app.buttons["automation-import-video"].tap()
        waitForCount(1)
        waitForAnalysis(1)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'media-'")).firstMatch.waitForExistence(timeout: 10))
    }

    func testThumbnailOpensAndClosesDetail() {
        launch("library")
        let thumbnail = media("fixture-orange")
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 30))
        #if os(macOS)
        clickMacMedia(thumbnail)
        let close = app.buttons["Back"]
        #else
        thumbnail.tap()
        let close = app.buttons["Close"]
        #endif
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 10))
        #if os(macOS)
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
        clickMacMedia(thumbnail)
        XCTAssertTrue(close.waitForExistence(timeout: 10), "The grid must remain usable after closing detail")
        close.click()
        #else
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: thumbnail)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 10), .completed)
        #endif
    }

    #if os(macOS)
    func testFullscreenMetadataRemainsUsableWhenBrowsingAndReopening() {
        launch("library")
        clickMacMedia(media("fixture-orange"))
        let close = app.buttons["Back"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        assertMacMetadataWaitsForScroll()
        revealMacMetadata(expectedTitle: "Orange inspiration")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "Dimensions")).firstMatch.isHittable)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "PNG")).firstMatch.isHittable)
        attachMacWindow("Metadata first reveal")

        // Returning to the panel must leave all content available.
        app.scrollViews["detail-scroll"].scroll(byDeltaX: 0, deltaY: 900)
        revealMacMetadata(expectedTitle: "Orange inspiration")

        // Browse in either direction: fixture ordering is not part of this test.
        // The title changes after the navigation animation, so an immediate read
        // can still return Orange and send a second key during the transition.
        app.typeKey(.rightArrow, modifierFlags: [])
        if !waitForMacMetadataTitle("Blue architecture", timeout: 2) {
            app.typeKey(.leftArrow, modifierFlags: [])
        }
        revealMacMetadata(expectedTitle: "Blue architecture")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "Dimensions")).firstMatch.isHittable)
        attachMacWindow("Metadata after browsing")
        close.click()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)

        clickMacMedia(media("fixture-orange"))
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        assertMacMetadataWaitsForScroll()
        revealMacMetadata(expectedTitle: "Orange inspiration")
        let pattern = app.buttons["Pattern: Fixture"]
        XCTAssertTrue(pattern.isHittable)
        pattern.click()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: close
        )], timeout: 10), .completed)
        XCTAssertEqual((app.searchFields.firstMatch.value as? String), "Fixture")
    }

    private func assertMacMetadataWaitsForScroll() {
        let scroll = app.scrollViews["detail-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        XCTAssertEqual(scroll.value as? String, "Metadata waiting for scroll")
        // Waiting at the image must never consume the below-the-fold reveal.
        let prematureReveal = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", "Metadata waiting for scroll"), object: scroll
        )
        prematureReveal.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [prematureReveal], timeout: 1), .completed)
    }

    private func waitForMacMetadataTitle(_ expectedTitle: String, timeout: TimeInterval) -> Bool {
        let title = app.staticTexts["detail-metadata-title"]
        let matching = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            title.exists && (title.value as? String)?.hasPrefix(expectedTitle) == true
        }, object: nil)
        return XCTWaiter.wait(for: [matching], timeout: timeout) == .completed
    }

    private func revealMacMetadata(expectedTitle: String, file: StaticString = #filePath, line: UInt = #line) {
        let scroll = app.scrollViews["detail-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertTrue(waitForMacMetadataTitle(expectedTitle, timeout: 10),
                      "Destination metadata must mount before scrolling", file: file, line: line)
        scroll.scroll(byDeltaX: 0, deltaY: -650)
        let title = app.staticTexts["detail-metadata-title"]
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            title.exists && title.isHittable && (title.value as? String)?.hasPrefix(expectedTitle) == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 10), .completed, file: file, line: line)
        XCTAssertTrue(app.buttons["Pattern: Fixture"].isHittable, file: file, line: line)
        XCTAssertEqual(scroll.value as? String, "Metadata revealed", file: file, line: line)
    }

    private func attachMacWindow(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    #endif

    func testSearchFindsMatchingMedia() {
        launch("library")
        XCTAssertTrue(media("fixture-orange").waitForExistence(timeout: 30))
        #if os(macOS)
        app.typeKey("f", modifierFlags: .command)
        #else
        if #available(iOS 26, *) { selectTab("Search") }
        #endif
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Orange")
        XCTAssertTrue(media("fixture-orange").waitForExistence(timeout: 10))
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: media("fixture-blue"))
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 10), .completed)
    }

    func testTrashAndRestoreWhereSupported() {
        launch("library")
        let thumbnail = media("fixture-orange")
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 30))
        #if os(macOS)
        clickMacMedia(thumbnail, rightClick: true)
        clickVisibleMenuItem("Delete")
        #else
        thumbnail.press(forDuration: 1)
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        delete.tap()
        let confirmation = app.alerts.buttons["Delete"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        confirmation.tap()
        #endif
        waitForCount(1)
        #if os(macOS)
        app.typeKey("z", modifierFlags: .command)
        waitForCount(2)
        XCTAssertTrue(media("fixture-orange").waitForExistence(timeout: 10))
        #endif
    }

    func testSpaceCanBeCreated() {
        launch("library")
        createAutomationSpace()
    }

    private func createAutomationSpace() {
        #if os(macOS)
        app.typeKey("n", modifierFlags: .command)
        #else
        selectTab("Spaces")
        let create = app.buttons["create-space"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        #endif
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        #if os(macOS)
        field.typeKey("a", modifierFlags: .command)
        #endif
        field.typeText("Automation space")
        #if os(macOS)
        field.typeText("\r")
        #else
        app.alerts.buttons["Create"].tap()
        #endif
        XCTAssertTrue(app.staticTexts["Automation space"].waitForExistence(timeout: 10))
    }

    func testSpaceAssignmentFiltersTheSpaceLibrary() {
        launch("library")
        createAutomationSpace()
        #if os(macOS)
        app.typeKey("1", modifierFlags: .command)
        #else
        selectTab("All")
        #endif
        let thumbnail = media("fixture-orange")
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 10))
        #if os(macOS)
        clickMacMedia(thumbnail, rightClick: true)
        clickVisibleMenuItem("Update Spaces")
        clickVisibleMenuItem("Automation space")
        app.typeKey("3", modifierFlags: .command)
        #else
        thumbnail.press(forDuration: 1)
        let update = app.buttons["Update Spaces"]
        XCTAssertTrue(update.waitForExistence(timeout: 10))
        update.tap()
        let space = app.buttons["Automation space"]
        XCTAssertTrue(space.waitForExistence(timeout: 10))
        space.tap()
        selectTab("Spaces")
        app.staticTexts["Automation space"].tap()
        #endif
        XCTAssertTrue(media("fixture-orange").waitForExistence(timeout: 10))
        let excluded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: media("fixture-blue"))
        XCTAssertEqual(XCTWaiter.wait(for: [excluded], timeout: 10), .completed)
    }

    #if os(iOS)
    private func selectTab(_ title: String) {
        let button = app.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Expected the \(title) tab button")
        button.tap()
    }
    #else
    private func clickMacMedia(_ item: XCUIElement, rightClick: Bool = false) {
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        let frame = item.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertTrue(window.contains(frame), "Media must be fully inside the app window before clicking: \(frame)")
        let attachment = XCTAttachment(string: "Media: \(item.identifier)\nFrame: \(frame)\nClick: \(center)\nWindow: \(window)")
        attachment.name = "Media click target"
        attachment.lifetime = .keepAlways
        add(attachment)
        // These cards contain an AppKit drag overlay and can lack an XCTest AX hit point.
        // Send a real mouse event to the visible card's center and assert its outcome.
        let point = item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        if rightClick { point.rightClick() } else { point.click() }
    }

    private func clickVisibleMenuItem(_ title: String) {
        let matches = app.menuItems.matching(identifier: title)
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            matches.allElementsBoundByIndex.contains(where: \.isHittable)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 10), .completed, "Expected a visible \(title) menu item")
        let item = matches.allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(item)
        item?.click()
    }
    #endif

}
