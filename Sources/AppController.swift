import Cocoa
import SwiftUI
import ApplicationServices

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var settings: AppSettings!
    private var resourceURL: URL!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var surfaces: [WallpaperSurface] = []
    private var displayConfigurations: [DisplayConfiguration] = []
    private var autoPauseState = DesktopVisibility.PauseState()
    private let iconReader = DesktopIconReader()
    private var icons: [CGRect] = []
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var sleeping = false
    private var sessionActive = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second launch opens the existing process's settings instead of creating another wallpaper.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.shoreline.wallpaper")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first {
            existing.activate(options: [.activateIgnoringOtherApps])
            NSApplication.shared.terminate(nil)
            return
        }
        Diagnostics.shared.record("app.start", "version=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "unknown") build=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "unknown") system=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        resourceURL = Bundle.main.resourceURL!.appendingPathComponent("Themes")
        let testSuite = ProcessInfo.processInfo.environment["SHORELINE_TEST_SUITE"]
        let defaults = testSuite.flatMap { $0.hasPrefix("local.shoreline.wallpaper.tests.") ? UserDefaults(suiteName: $0) : nil } ?? .standard
        do { settings = try AppSettings(resourceURL: resourceURL, defaults: defaults) }
        catch {
            Diagnostics.shared.record("app.resource-error", error.localizedDescription)
            let alert = NSAlert()
            alert.messageText = "无法载入主题资源"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        settings.onChange = { [weak self] change in self?.apply(change) }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "water.waves", accessibilityDescription: "岸屿 Shoreline")
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = true; self?.updatePlayback()
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = false; self?.tick()
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sessionActive = false; self?.updatePlayback()
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sessionActive = true; self?.tick()
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.surfaces.forEach { $0.window.orderFrontRegardless() }
            self?.tick()
        })
        rebuildSurfaces(reason: "startup")
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        tick()
        showSettings()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        Diagnostics.shared.record("app.exit")
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        surfaces.removeAll()
        if let suite = ProcessInfo.processInfo.environment["SHORELINE_TEST_SUITE"], suite.hasPrefix("local.shoreline.wallpaper.tests.") {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        Diagnostics.shared.flush()
    }

    private func apply(_ change: AppSettings.Change) {
        switch change {
        case .theme:
            settings.renderError = nil
            surfaces.forEach { $0.renderer.load(theme: settings.theme, parameters: settings.currentParameters, reason: "theme-change") }
        case .parameters:
            surfaces.forEach { $0.renderer.setParameters(settings.currentParameters) }
        case .playback: updatePlayback()
        }
    }

    @objc private func screenParametersChanged() {
        let screens = NSScreen.screens
        guard screens.map(DisplayConfiguration.init) != displayConfigurations else {
            Diagnostics.shared.record("surfaces.reused", "display geometry unchanged")
            for (surface, screen) in zip(surfaces, screens) { surface.screen = screen }
            updatePlayback()
            return
        }
        rebuildSurfaces(reason: "display-configuration-changed")
    }

    @objc private func reloadWallpaper() { rebuildSurfaces(reason: "manual-reload") }

    private func rebuildSurfaces(reason: String) {
        let screens = NSScreen.screens
        displayConfigurations = screens.map(DisplayConfiguration.init)
        Diagnostics.shared.record("surfaces.rebuild", "reason=\(reason) screens=\(displayConfigurations)")
        surfaces.removeAll()
        settings.renderError = nil
        surfaces = screens.map { screen in
            let surface = WallpaperSurface(screen: screen, resourceURL: resourceURL)
            surface.renderer.onError = { [weak self] in self?.settings.renderError = $0 }
            surface.renderer.load(theme: settings.theme, parameters: settings.currentParameters, reason: reason)
            surface.window.orderFrontRegardless()
            return surface
        }
        settings.screenCount = surfaces.count
        updateIcons()
        updatePlayback()
    }

    private func tick() {
        updatePlayback()
        guard !sleeping, sessionActive else { return }
        iconReader.scan { [weak self] result in
            guard let self else { return }
            let needsPermission: Bool
            let status: String
            switch result {
            case .permissionRequired:
                needsPermission = true
                status = "需要辅助功能权限来感知桌面图标"
                self.icons = []
            case .unavailable:
                needsPermission = false
                status = "暂未找到 Finder 桌面，正在重试…"
                self.icons = []
            case .found(let rectangles):
                needsPermission = false
                status = "已连接 Finder · 检测到 \(rectangles.count) 个桌面图标"
                self.icons = rectangles
            }
            if self.settings.needsPermission != needsPermission { self.settings.needsPermission = needsPermission }
            if self.settings.iconStatus != status { self.settings.iconStatus = status }
            self.updateIcons()
        }
    }

    private func updateIcons() {
        guard let primary = NSScreen.screens.first else { return }
        for surface in surfaces {
            surface.renderer.setIcons(DesktopCoordinates.rectangles(icons, screen: surface.screen.frame,
                primaryTop: primary.frame.maxY, scale: surface.screen.backingScaleFactor))
        }
    }

    private func updatePlayback() {
        let inactive = settings.paused || sleeping || !sessionActive
        let covered = settings.autoPause && !inactive ? DesktopVisibility.coveredDisplays(surfaces.map(\.screen)) : []
        let stableCovered = autoPauseState.update(covered, at: ProcessInfo.processInfo.systemUptime)
        for surface in surfaces {
            surface.renderer.setPaused(inactive || stableCovered.contains(DisplayConfiguration(screen: surface.screen).identifier))
        }
    }

    @objc private func showSettings() {
        guard settings != nil else { return }
        if settingsWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 660, height: 760),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "岸屿 Shoreline"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings, resourceURL: resourceURL,
                requestPermission: { [weak self] in self?.requestPermission() }))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func requestPermission() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        addItem("岸屿设置…", action: #selector(showSettings), to: menu, key: ",")
        menu.addItem(.separator())
        for theme in settings.themes {
            let item = addItem(theme.name, action: #selector(selectTheme(_:)), to: menu)
            item.representedObject = theme.id
            item.state = settings.themeID == theme.id ? .on : .off
        }
        menu.addItem(.separator())
        addItem(settings.paused ? "继续动画" : "暂停动画", action: #selector(togglePause), to: menu)
        addItem("换一张", action: #selector(shuffle), to: menu)
        addItem("重新载入壁纸", action: #selector(reloadWallpaper), to: menu)
        addItem("打开日志文件夹…", action: #selector(openLogs), to: menu)
        menu.addItem(.separator())
        addItem("退出岸屿", action: #selector(quit), to: menu, key: "q")
    }

    @discardableResult private func addItem(_ title: String, action: Selector, to menu: NSMenu, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func selectTheme(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { settings.themeID = id } }
    @objc private func togglePause() { settings.paused.toggle() }
    @objc private func shuffle() { settings.shuffle() }
    @objc private func openLogs() {
        try? FileManager.default.createDirectory(at: Diagnostics.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Diagnostics.directory)
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
