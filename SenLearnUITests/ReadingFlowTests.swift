import XCTest

final class ReadingFlowTests: XCTestCase {
    @MainActor
    func testCompactReadingAndSettings() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-library"]
        app.launch()
        let sample = app.buttons["library.sample"]
        for _ in 0..<4 where !sample.isHittable { app.swipeUp() }
        XCTAssertTrue(sample.waitForExistence(timeout: 8))
        sample.tap()
        let squirrel = app.buttons["squirrel"].firstMatch
        XCTAssertTrue(squirrel.waitForExistence(timeout: 35))
        squirrel.tap()
        XCTAssertEqual(app.staticTexts["reader.selectedWord"].label, "squirrel")
        XCTAssertTrue(app.buttons["reader.replay"].isHittable)
        capture("reader-compact", app)
        if app.buttons["停止"].exists { app.buttons["停止"].tap() }
        app.buttons["reader.settings"].tap()
        let night = app.buttons["settings.theme.night"]
        let settings = app.scrollViews["settings.scroll"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        for _ in 0..<6 where !night.isHittable { settings.swipeUp() }
        XCTAssertTrue(night.isHittable)
        night.tap()
        app.buttons["完成"].tap()
        XCTAssertEqual(app.staticTexts["reader.selectedWord"].label, "squirrel")
        XCTAssertEqual(app.staticTexts["reader.pageCounter"].label, "1 / 2")
        capture("reader-compact-night", app)
    }

    @MainActor
    func testImportOCRReadingThemesAndRestore() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-library"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let sample = app.buttons["library.sample"]
        XCTAssertTrue(sample.waitForExistence(timeout: 10))
        if !sample.isHittable { app.swipeUp() }
        sample.tap()
        let squirrel = app.buttons["squirrel"].firstMatch
        XCTAssertTrue(squirrel.waitForExistence(timeout: 40), app.debugDescription)
        squirrel.tap()
        XCTAssertEqual(app.staticTexts["reader.selectedWord"].label, "squirrel")
        XCTAssertTrue(app.buttons["reader.sentence"].isEnabled)
        app.buttons["reader.sentence"].tap()
        capture("reader-forest", app)
        if app.buttons["停止"].exists { app.buttons["停止"].tap() }
        app.buttons["reader.next"].tap()
        let tiny = app.buttons["tiny"].firstMatch
        XCTAssertTrue(tiny.waitForExistence(timeout: 35))
        tiny.tap()
        if app.buttons["停止"].exists { app.buttons["停止"].tap() }
        XCTAssertEqual(app.staticTexts["reader.pageCounter"].label, "2 / 2")

        app.buttons["reader.settings"].tap()
        XCTAssertTrue(app.buttons["settings.theme.night"].waitForExistence(timeout: 5))
        app.buttons["settings.theme.night"].tap()
        capture("settings-night", app)
        app.buttons["完成"].tap()
        XCTAssertEqual(app.staticTexts["reader.selectedWord"].label, "tiny")
        XCTAssertEqual(app.staticTexts["reader.pageCounter"].label, "2 / 2")
        capture("reader-night", app)

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["reader.pageCounter"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["reader.pageCounter"].label, "2 / 2")
        XCTAssertFalse(app.buttons["停止"].exists, "Restoring a book must never auto-play.")
        app.buttons["reader.settings"].tap()
        XCTAssertEqual(app.buttons["settings.theme.night"].value as? String, "已选中")
        app.buttons["恢复默认主题"].tap()
        app.buttons["完成"].tap()
        XCTAssertEqual(app.staticTexts["reader.pageCounter"].label, "2 / 2")

        XCUIDevice.shared.orientation = .portrait
        capture("reader-portrait", app)
        app.buttons["reader.back"].tap()
        XCTAssertTrue(app.staticTexts["我的书架"].waitForExistence(timeout: 5))
        capture("library", app)
    }

    @MainActor
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
