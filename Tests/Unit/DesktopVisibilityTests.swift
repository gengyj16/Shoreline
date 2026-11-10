import XCTest
import Cocoa

final class DesktopVisibilityTests: XCTestCase {
    private let area = CGRect(x: 0, y: 30, width: 1440, height: 850)
    private let shell: Set<pid_t> = [99]

    private func window(_ identifier: Int, owner: pid_t = 1, layer: Int = 0,
                        frame: CGRect? = nil, alpha: Double = 1, onScreen: Bool = true) -> DesktopVisibility.Window {
        DesktopVisibility.Window(identifier: identifier, owner: owner, layer: layer,
                                 frame: frame ?? area, alpha: alpha, onScreen: onScreen)
    }

    func testBackgroundFullScreenWindowPausesWithSmallForegroundWindow() {
        let windows = [window(2, owner: 2, frame: CGRect(x: 200, y: 150, width: 800, height: 600)), window(1)]
        XCTAssertTrue(DesktopVisibility.isCovered(windows, area: area, hitWindows: [2, 1, 1, 1, 1, 1, 1, 1, 1], shellProcesses: shell))
    }

    func testShowDesktopResumesEvenWhenWindowBoundsRemainFullScreen() {
        let windows = [window(3, owner: 99, layer: 18), window(1)]
        XCTAssertFalse(DesktopVisibility.isCovered(windows, area: area, hitWindows: Array(repeating: 3, count: 9), shellProcesses: shell))
    }

    func testStageManagerDesktopOrThumbnailRemainsAnimated() {
        let windows = [window(1), window(2, owner: 2, frame: CGRect(x: 200, y: 150, width: 800, height: 600)),
                       window(3, owner: 99, layer: 8), window(4, owner: 3, layer: -2147483603)]
        XCTAssertFalse(DesktopVisibility.isCovered(windows, area: area, hitWindows: [2, 3, 4, 4, 4, 4, 4, 4, 4], shellProcesses: shell))
    }

    func testMinimizedAndOtherSpaceWindowsDoNotPause() {
        XCTAssertFalse(DesktopVisibility.isCovered([window(1, onScreen: false)], area: area,
                       hitWindows: Array(repeating: 1, count: 9), shellProcesses: shell))
    }

    func testOtherDisplayAndTransparentWindowsDoNotPause() {
        XCTAssertFalse(DesktopVisibility.hasCoveringWindow([window(1, frame: area.offsetBy(dx: 1440, dy: 0))], area: area, shellProcesses: shell))
        XCTAssertFalse(DesktopVisibility.hasCoveringWindow([window(1, alpha: 0.5)], area: area, shellProcesses: shell))
    }

    func testFloatingApplicationPanelsOverFullScreenWindowStayPaused() {
        let windows = [window(1), window(2, owner: 2, layer: 3)]
        XCTAssertTrue(DesktopVisibility.isCovered(windows, area: area, hitWindows: [2, 1, 1, 1, 1, 1, 1, 1, 1], shellProcesses: shell))
    }

    func testUnknownOrIncompleteHitTestsKeepDesktopAnimated() {
        XCTAssertFalse(DesktopVisibility.isCovered([window(1)], area: area, hitWindows: [1], shellProcesses: shell))
        XCTAssertFalse(DesktopVisibility.isCovered([window(1)], area: area, hitWindows: Array(repeating: 0, count: 9), shellProcesses: shell))
    }

    func testProbePointsCoverEdgesWithoutRoundedWindowCorners() {
        let points = DesktopVisibility.samplePoints(in: area)
        XCTAssertEqual(points.count, 9)
        XCTAssertTrue(points.allSatisfy(area.contains))
        XCTAssertTrue(points.contains(CGPoint(x: area.minX + 1, y: area.midY)))
        XCTAssertTrue(points.contains(CGPoint(x: area.maxX - 1, y: area.midY)))
    }

    func testBriefStageManagerTransitionDoesNotPauseAndDesktopResumesImmediately() {
        var state = DesktopVisibility.PauseState()
        XCTAssertEqual(state.update([1], at: 0), [])
        XCTAssertEqual(state.update([1], at: 0.2), [])
        XCTAssertEqual(state.update([], at: 0.3), [])
        XCTAssertEqual(state.update([1], at: 0.4), [])
        XCTAssertEqual(state.update([1], at: 1.0), [1])
        XCTAssertEqual(state.update([], at: 1.01), [])
    }

    func testDisplayPauseTimersAreIndependent() {
        var state = DesktopVisibility.PauseState()
        XCTAssertEqual(state.update([1], at: 0), [])
        XCTAssertEqual(state.update([1, 2], at: 0.6), [1])
        XCTAssertEqual(state.update([1, 2], at: 1.2), [1, 2])
        XCTAssertEqual(state.update([2], at: 1.3), [2])
    }
}
