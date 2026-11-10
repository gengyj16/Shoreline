import XCTest
import Cocoa

final class DesktopTests: XCTestCase {
    func testDisplayIdentityAndGeometryControlRebuild() {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let original = DisplayConfiguration(identifier: 1, frame: frame, scale: 2)
        XCTAssertEqual(original, DisplayConfiguration(identifier: 1, frame: frame, scale: 2))
        XCTAssertNotEqual(original, DisplayConfiguration(identifier: 2, frame: frame, scale: 2))
        XCTAssertNotEqual(original, DisplayConfiguration(identifier: 1, frame: frame, scale: 1))
        XCTAssertNotEqual(original, DisplayConfiguration(identifier: 1, frame: frame.offsetBy(dx: 20, dy: 0), scale: 2))
        XCTAssertNotEqual(original, DisplayConfiguration(identifier: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 2))
    }

    func testRetinaCoordinateConversionAcrossDisplays() {
        let result = DesktopCoordinates.rectangles([CGRect(x: -100, y: -200, width: 60, height: 80)],
            screen: CGRect(x: -800, y: 900, width: 800, height: 600), primaryTop: 900, scale: 2)
        XCTAssertEqual(result, [[1400, 800, 1520, 960]])
    }

    func testClipsIconsAtDisplayEdgesAndExcludesOtherDisplays() {
        let result = DesktopCoordinates.rectangles([
            CGRect(x: -10, y: 20, width: 40, height: 50),
            CGRect(x: 1200, y: 20, width: 40, height: 50)
        ], screen: CGRect(x: 0, y: 0, width: 900, height: 600), primaryTop: 600, scale: 1)
        XCTAssertEqual(result, [[0, 20, 30, 70]])
    }

    func testSettingsPersistAndClampInvalidValues() throws {
        let suite = "local.shoreline.unit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = try XCTUnwrap(Bundle(for: Self.self).resourceURL)
        let settings = try AppSettings(resourceURL: url, defaults: defaults)
        XCTAssertEqual(settings.themes.count, 2)
        settings.themeID = "beach"
        var reloads = 0
        settings.onChange = { change in if case .theme = change { reloads += 1 } }
        settings.themeID = "beach"
        XCTAssertEqual(reloads, 0)
        let sigma = try XCTUnwrap(settings.theme.groups.flatMap(\.params).first { $0.key == "sigma" })
        settings.setParameter(sigma, value: 9999)
        XCTAssertEqual(settings.currentParameters["sigma"], 200)
        XCTAssertEqual(try AppSettings(resourceURL: url, defaults: defaults).currentParameters["sigma"], 200)
        settings.setParameter(sigma, value: .nan)
        XCTAssertEqual(settings.currentParameters["sigma"], 85)
        settings.reset()
        XCTAssertEqual(settings.currentParameters["sigma"], 85)
        XCTAssertEqual(settings.currentParameters["seed"], 421337)
    }
}
