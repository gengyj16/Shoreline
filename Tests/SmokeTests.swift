import Cocoa
import WebKit

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let message): return message } }
}

@main struct SmokeTests {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let runner = SmokeRunner()
        app.delegate = runner
        app.run()
    }
}

final class SmokeRunner: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var renderer: WallpaperRenderer!
    private var errors: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                try await run()
                Diagnostics.shared.flush()
                print("PASS — settings, coordinates, both WebKit themes, icon updates, animation, pause and resume, zero paused animation callbacks and WebGL draw submissions")
                exit(0)
            } catch {
                fputs("FAIL — \(error)\n", stderr)
                exit(1)
            }
        }
    }

    @MainActor private func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw CheckFailure.failed(message) }
    }

    @MainActor private func js(_ source: String) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            renderer.webView.evaluateJavaScript(source) { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value ?? NSNull()) }
            }
        }
    }

    @MainActor private func waitFor(_ expression: String) async throws {
        for _ in 0..<100 {
            if (try? await js(expression)) as? Bool == true { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let state = try? await js("JSON.stringify({icons: typeof icons === 'undefined' ? null : icons, frameN: typeof frameN === 'undefined' ? null : frameN, paused: typeof paused === 'undefined' ? null : paused, curMix: typeof curMix === 'undefined' ? null : curMix})")
        throw CheckFailure.failed("Timed out waiting for \(expression). State \(String(describing: state)). Errors \(errors)")
    }

    @MainActor private func snapshot(_ path: URL) async throws {
        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            renderer.webView.takeSnapshot(with: nil) { image, error in
                if let error { continuation.resume(throwing: error) }
                else if let image { continuation.resume(returning: image) }
                else { continuation.resume(throwing: CheckFailure.failed("Empty snapshot")) }
            }
        }
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            throw CheckFailure.failed("Snapshot encoding failed")
        }
        try png.write(to: path)
    }

    @MainActor private func run() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let resources = root.appendingPathComponent("Resources/Themes")
        let output = root.appendingPathComponent(".build/qa")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let logDirectory = output.appendingPathComponent("log-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: logDirectory) }
        let diagnostics = Diagnostics(directory: logDirectory)
        diagnostics.record("test.persistence", "message")
        diagnostics.flush()
        let log = logDirectory.appendingPathComponent("application.log")
        try check(try String(contentsOf: log, encoding: .utf8).contains("test.persistence"), "Persistent diagnostic log")
        try Data(repeating: 0, count: 1_048_576).write(to: log)
        diagnostics.record("test.rotation")
        diagnostics.flush()
        try check(FileManager.default.fileExists(atPath: logDirectory.appendingPathComponent("application.previous.log").path), "Diagnostic log rotation")
        try check(try String(contentsOf: log, encoding: .utf8).contains("test.rotation"), "Diagnostic log continues after rotation")
        let suite = "local.shoreline.smoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = try AppSettings(resourceURL: resources, defaults: defaults)
        if let screen = NSScreen.screens.first {
            let desktop = DesktopWindow(screen: screen)
            try check(desktop.ignoresMouseEvents && !desktop.canBecomeKey, "Desktop window leaves Finder interaction available")
            try check(desktop.level.rawValue > Int(CGWindowLevelForKey(.desktopWindow)) &&
                      desktop.level.rawValue < Int(CGWindowLevelForKey(.desktopIconWindow)), "Wallpaper stacking below desktop icons")
            try check(desktop.frame == screen.frame && desktop.collectionBehavior.contains(.canJoinAllSpaces), "Desktop window screen geometry and Spaces")
            desktop.close()
        }
        try check(settings.themes.count == 2, "Theme registry")
        let sigma = settings.theme.groups.flatMap(\.params).first { $0.key == "sigma" }!
        settings.setParameter(sigma, value: 999)
        try check(settings.currentParameters["sigma"] == 200, "Parameter clamping")
        let restored = try AppSettings(resourceURL: resources, defaults: defaults)
        try check(restored.currentParameters["sigma"] == 200, "Settings persistence")
        settings.reset()
        try check(settings.currentParameters["sigma"] == 85, "Default reset")
        let coordinates = DesktopCoordinates.rectangles([CGRect(x: -100, y: -200, width: 60, height: 80)],
            screen: CGRect(x: -800, y: 900, width: 800, height: 600), primaryTop: 900, scale: 2)
        try check(coordinates == [[1400, 800, 1520, 960]], "Negative-origin / vertically arranged Retina display")
        let clipped = DesktopCoordinates.rectangles([CGRect(x: -10, y: 20, width: 40, height: 50)],
            screen: CGRect(x: 0, y: 0, width: 900, height: 600), primaryTop: 600, scale: 1)
        try check(clipped == [[0, 20, 30, 70]], "Cross-display clipping")

        window = NSWindow(contentRect: CGRect(x: 140, y: 140, width: 960, height: 600),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        renderer = WallpaperRenderer(resourceURL: resources)
        renderer.onError = { [weak self] in self?.errors.append($0) }
        window.contentView = renderer.webView
        renderer.webView.frame = CGRect(x: 0, y: 0, width: 960, height: 600)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        for theme in settings.themes {
            print("Testing \(theme.id)…")
            renderer.setPaused(false)
            renderer.load(theme: theme, parameters: theme.defaults.merging(["seed": 421337]) { old, _ in old })
            try await waitFor("typeof iconsSeen !== 'undefined' && iconsSeen && frameN > 2")
            try check(renderer.webView.underPageBackgroundColor != NSColor.white, "\(theme.id) loading backdrop follows theme")
            let scale = try await js("window.devicePixelRatio") as! Double
            renderer.setIcons([[120 * scale, 90 * scale, 200 * scale, 180 * scale],
                               [780 * scale, 100 * scale, 860 * scale, 195 * scale],
                               [780 * scale, 260 * scale, 860 * scale, 355 * scale]])
            try await waitFor("icons.length === 3 && icons[0].x === 120 && curMix === 1")
            try await snapshot(output.appendingPathComponent("\(theme.id).png"))
            _ = try await js("""
            (() => {
              window.pauseMetrics = {callbacks: 0, draws: 0};
              const originalFrame = window.requestAnimationFrame;
              window.requestAnimationFrame = callback => originalFrame.call(window, time => {
                window.pauseMetrics.callbacks++;
                callback(time);
              });
              for (const name of ['drawArrays', 'drawElements']) {
                const originalDraw = gl[name].bind(gl);
                gl[name] = (...args) => { window.pauseMetrics.draws++; return originalDraw(...args); };
              }
            })();
            """)
            let before = try await js("frameN") as! Int
            try await Task.sleep(nanoseconds: 250_000_000)
            try check((try await js("frameN") as! Int) > before, "\(theme.id) animation advances")
            renderer.setPaused(true)
            try await waitFor("paused === true && frameRequest === 0")
            let pausedFrame = try await js("frameN") as! Int
            let pausedMetrics = try await js("JSON.stringify(window.pauseMetrics)") as! String
            try await Task.sleep(nanoseconds: 350_000_000)
            try check((try await js("frameN") as! Int) == pausedFrame, "\(theme.id) pause")
            try check((try await js("JSON.stringify(window.pauseMetrics)") as! String) == pausedMetrics,
                      "\(theme.id) paused animation callbacks and WebGL draws stop")
            renderer.setIcons([[450 * scale, 300 * scale, 530 * scale, 390 * scale]])
            try await waitFor("icons.length === 1 && icons[0].x === 450 && curMix === 1")
            renderer.setParameters(theme.defaults.merging(["sigma": 120]) { _, new in new })
            try await waitFor("P.sigma === 120")
            renderer.setIcons([])
            try await waitFor("icons.length === 0")
            renderer.setPaused(false)
            try await waitFor("frameN > \(pausedFrame)")
            _ = try await js("setAnimationPaused(true)")
            try await waitFor("paused && frameRequest === 0")
            _ = try await js("setAnimationPaused(false)")
            try await waitFor("!paused && frameRequest !== 0")
            try check(errors.isEmpty, "\(theme.id) JavaScript errors \(errors)")
        }
        window.close()
    }
}
