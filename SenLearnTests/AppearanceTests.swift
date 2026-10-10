import XCTest
@testable import SenLearn

@MainActor
final class AppearanceTests: XCTestCase {
    func testInvalidThemeFallsBackAndResetPreservesReadingPreferences() {
        let suite = "SenLearnTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unknown-theme", forKey: "appearance.theme")
        let settings = AppearanceSettings(defaults: defaults)
        XCTAssertEqual(settings.theme, .forest)
        settings.reduceMotion = true
        settings.parentPanel = true
        settings.theme = .night
        XCTAssertEqual(AppearanceSettings(defaults: defaults).theme, .night)
        settings.resetTheme()
        let restored = AppearanceSettings(defaults: defaults)
        XCTAssertEqual(restored.theme, .forest)
        XCTAssertTrue(restored.parentPanel)
        XCTAssertTrue(restored.reduceMotion)
    }
}
