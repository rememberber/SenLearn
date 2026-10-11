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
    func testRotationPreviewCancelSaveAndReadAgain() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-library"]
        app.launch()
        let sample = app.buttons["library.sample"]
        XCTAssertTrue(sample.waitForExistence(timeout: 10))
        if !sample.isHittable { app.swipeUp() }
        sample.tap()
        let squirrel = app.buttons["squirrel"].firstMatch
        XCTAssertTrue(squirrel.waitForExistence(timeout: 40))
        squirrel.tap()
        app.buttons["reader.more"].tap()
        app.buttons["reader.rotate"].tap()
        XCTAssertFalse(app.buttons["rotation.save"].isEnabled)
        app.buttons["rotation.right"].tap()
        capture("rotation-preview", app)
        app.buttons["rotation.cancel"].tap()
        XCTAssertEqual(app.staticTexts["reader.selectedWord"].label, "squirrel")
        app.buttons["reader.more"].tap()
        app.buttons["reader.rotate"].tap()
        app.buttons["rotation.right"].tap()
        app.buttons["rotation.save"].tap()
        XCTAssertTrue(app.buttons["reader.more"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["reader.selectedWord"].exists)
        XCTAssertEqual(app.staticTexts["reader.pageCounter"].label, "1 / 2")
        capture("reader-rotated", app)
        app.buttons["reader.more"].tap()
        let rotate = app.buttons["reader.rotate"]
        let enabled = NSPredicate(format: "exists == true AND enabled == true")
        expectation(for: enabled, evaluatedWith: rotate)
        waitForExpectations(timeout: 40)
        rotate.tap()
        app.buttons["rotation.left"].tap()
        app.buttons["rotation.save"].tap()
        XCTAssertTrue(squirrel.waitForExistence(timeout: 40))
        squirrel.tap()
        XCTAssertEqual(app.staticTexts["reader.selectedWord"].label, "squirrel")
        capture("reader-after-rotation", app)
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(squirrel.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["reader.pageCounter"].label, "1 / 2")
    }

    @MainActor
    func testKokoroSettingsBilingualPreviewAndExplicitSystemChoice() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-library"]
        app.launch()
        app.buttons["library.settings"].tap()
        let chinese = app.buttons["settings.testChinese"]
        let scroll = app.scrollViews["settings.scroll"]
        for _ in 0..<6 where !chinese.isHittable { scroll.swipeUp() }
        XCTAssertTrue(chinese.isHittable)
        XCTAssertTrue(app.staticTexts["中文和英文声音已随应用安装，可直接离线朗读。"].exists)
        let styles = app.segmentedControls["settings.voiceStyle"]
        XCTAssertTrue(styles.buttons["童趣女声"].exists)
        styles.buttons["童趣女声"].tap()
        chinese.tap()
        XCTAssertTrue(app.staticTexts["settings.synthesisSummary"].waitForExistence(timeout: 40))
        capture("kokoro-settings", app)
        if app.buttons["停止试听"].exists { app.buttons["停止试听"].tap() }
        app.buttons["settings.testEnglish"].tap()
        styles.buttons["清亮女声"].tap()
        XCTAssertFalse(app.buttons["停止试听"].exists, "Changing style must stop the previous preview.")
        app.segmentedControls["settings.speechEngine"].buttons["系统声音"].tap()
        XCTAssertFalse(app.buttons["停止试听"].exists)
        app.segmentedControls["settings.speechEngine"].buttons["Kokoro 离线声音"].tap()
        app.buttons["完成"].tap()
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["library.settings"].tap()
        for _ in 0..<6 where !chinese.isHittable { scroll.swipeUp() }
        XCTAssertTrue(app.staticTexts["中文和英文声音已随应用安装，可直接离线朗读。"].exists)
        XCTAssertTrue(app.staticTexts["声音稍亮一些，轻快清晰。"].exists)
        app.segmentedControls["settings.voiceStyle"].buttons["童趣女声"].tap()
    }

    @MainActor
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
