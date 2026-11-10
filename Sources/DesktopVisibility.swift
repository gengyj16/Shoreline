import Cocoa
import CoreGraphics

enum DesktopVisibility {
    struct PauseState {
        private var coveredSince: [UInt32: TimeInterval] = [:]

        mutating func update(_ covered: Set<UInt32>, at time: TimeInterval) -> Set<UInt32> {
            coveredSince = coveredSince.filter { covered.contains($0.key) }
            var paused: Set<UInt32> = []
            for display in covered {
                let start = coveredSince[display] ?? time
                coveredSince[display] = start
                if time - start >= 0.5 { paused.insert(display) }
            }
            return paused
        }
    }

    struct Window {
        let identifier: Int
        let owner: pid_t
        let layer: Int
        let frame: CGRect
        let alpha: Double
        let onScreen: Bool
    }

    static func coveredDisplays(_ screens: [NSScreen]) -> Set<UInt32> {
        guard let primary = NSScreen.screens.first,
              let descriptions = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let windows = descriptions.compactMap { info -> Window? in
            guard let identifier = info[kCGWindowNumber as String] as? Int,
                  let owner = info[kCGWindowOwnerPID as String] as? Int32,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return Window(identifier: identifier, owner: owner, layer: layer, frame: frame,
                          alpha: info[kCGWindowAlpha as String] as? Double ?? 0,
                          onScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false)
        }
        let shellProcesses = Set(["com.apple.dock", "com.apple.WindowManager"].flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).map(\.processIdentifier)
        })
        var covered: Set<UInt32> = []
        for screen in screens {
            let visible = screen.visibleFrame
            let area = CGRect(x: visible.minX, y: primary.frame.maxY - visible.maxY,
                              width: visible.width, height: visible.height)
            guard hasCoveringWindow(windows, area: area, shellProcesses: shellProcesses) else { continue }
            // Hit testing uses the Window Server's presented positions, including Show Desktop
            // and Stage Manager transforms that can differ from a window's reported bounds.
            let hits = samplePoints(in: visible).map {
                NSWindow.windowNumber(at: $0, belowWindowWithWindowNumber: 0)
            }
            if isCovered(windows, area: area, hitWindows: hits, shellProcesses: shellProcesses) {
                covered.insert(DisplayConfiguration(screen: screen).identifier)
            }
        }
        return covered
    }

    static func hasCoveringWindow(_ windows: [Window], area: CGRect, shellProcesses: Set<pid_t>) -> Bool {
        windows.contains {
            $0.onScreen && $0.layer == 0 && $0.alpha >= 0.99 && !shellProcesses.contains($0.owner)
                && $0.frame.insetBy(dx: -4, dy: -4).contains(area)
        }
    }

    static func isCovered(_ windows: [Window], area: CGRect, hitWindows: [Int], shellProcesses: Set<pid_t>) -> Bool {
        guard hasCoveringWindow(windows, area: area, shellProcesses: shellProcesses), hitWindows.count == 9 else { return false }
        let byIdentifier = Dictionary(uniqueKeysWithValues: windows.map { ($0.identifier, $0) })
        return hitWindows.allSatisfy { identifier in
            guard let window = byIdentifier[identifier] else { return false }
            return window.onScreen && window.layer >= 0 && window.layer < Int(CGWindowLevelForKey(.dockWindow))
                && window.alpha >= 0.99 && !shellProcesses.contains(window.owner)
        }
    }

    static func samplePoints(in frame: CGRect) -> [CGPoint] {
        let corners = frame.insetBy(dx: min(16, frame.width / 4), dy: min(16, frame.height / 4))
        return [CGPoint(x: frame.midX, y: frame.midY),
                CGPoint(x: frame.minX + 1, y: frame.midY), CGPoint(x: frame.maxX - 1, y: frame.midY),
                CGPoint(x: frame.midX, y: frame.minY + 1), CGPoint(x: frame.midX, y: frame.maxY - 1),
                CGPoint(x: corners.minX, y: corners.minY), CGPoint(x: corners.maxX, y: corners.minY),
                CGPoint(x: corners.minX, y: corners.maxY), CGPoint(x: corners.maxX, y: corners.maxY)]
    }
}
