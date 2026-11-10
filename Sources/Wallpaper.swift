import Cocoa
import WebKit

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hasShadow = false
        isOpaque = true
        backgroundColor = .systemTeal
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        setFrame(screen.frame, display: false)
    }
}

private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var owner: WallpaperRenderer?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receive(message.body)
    }
}

private final class ThemeSchemeHandler: NSObject, WKURLSchemeHandler {
    let root: URL
    init(root: URL) { self.root = root.resolvingSymlinksInPath() }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.host == "themes" else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let file = root.appendingPathComponent(url.path).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.path + "/") else {
            urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }
        do {
            let data = try Data(contentsOf: file)
            let types = ["html": "text/html", "js": "application/javascript", "json": "application/json",
                         "png": "image/png", "webp": "image/webp"]
            let response = URLResponse(url: url, mimeType: types[file.pathExtension] ?? "application/octet-stream",
                                       expectedContentLength: data.count, textEncodingName: nil)
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch { urlSchemeTask.didFailWithError(error) }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

final class WallpaperRenderer: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private let resourceURL: URL
    private var ready = false
    private var theme: Theme?
    private var parameters: [String: Double] = [:]
    private var rectangles: [[Double]] = []
    private var paused = false
    private var recoveryAttempts = 0
    private let identifier = String(UUID().uuidString.prefix(8))
    var onError: ((String) -> Void)?
    var onReady: (() -> Void)?

    init(resourceURL: URL) {
        self.resourceURL = resourceURL
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // A shared local origin lets WebGL upload bundled sprites without file:// canvas tainting.
        configuration.setURLSchemeHandler(ThemeSchemeHandler(root: resourceURL), forURLScheme: "shoreline")
        let handler = WeakScriptHandler()
        configuration.userContentController.add(handler, name: "shoreline")
        configuration.userContentController.addUserScript(WKUserScript(source: """
        (() => {
          const listeners = [];
          window.chrome = { webview: {
            addEventListener: (type, callback) => { if (type === 'message') listeners.push(callback); },
            postMessage: message => window.webkit.messageHandlers.shoreline.postMessage(message)
          }};
          window.shorelineReceive = message => {
            for (const listener of listeners) listener({data: JSON.stringify(message)});
          };
          const originalError = console.error;
          console.error = (...args) => {
            window.webkit.messageHandlers.shoreline.postMessage({error: args.map(String).join(' ')});
            originalError.apply(console, args);
          };
          addEventListener('error', event => {
            window.webkit.messageHandlers.shoreline.postMessage({error: event.error?.stack || event.message || '主题脚本加载失败'});
          });
          addEventListener('unhandledrejection', event => {
            window.webkit.messageHandlers.shoreline.postMessage({error: String(event.reason)});
          });
          for (const name of ['webglcontextlost', 'webglcontextrestored']) {
            addEventListener(name, () => window.webkit.messageHandlers.shoreline.postMessage({event: name}), true);
          }
        })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        handler.owner = self
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        webView.allowsBackForwardNavigationGestures = false
    }

    func load(theme: Theme, parameters: [String: Double], reason: String = "theme-load") {
        self.theme = theme
        self.parameters = parameters
        ready = false
        Diagnostics.shared.record("renderer.load", "id=\(identifier) theme=\(theme.id) reason=\(reason)")
        webView.underPageBackgroundColor = theme.id == "beach"
            ? NSColor(calibratedRed: 0.10, green: 0.64, blue: 0.77, alpha: 1)
            : NSColor(calibratedRed: 0.65, green: 0.77, blue: 0.43, alpha: 1)
        var components = URLComponents(string: "shoreline://themes/\(theme.page)")!
        components.queryItems = [URLQueryItem(name: "wallpaper", value: "1")]
        webView.load(URLRequest(url: components.url!))
    }

    func setParameters(_ values: [String: Double]) {
        guard values != parameters else { return }
        parameters = values
        send(["t": "settings", "v": parameters])
    }

    func setIcons(_ values: [[Double]]) {
        guard rectangles != values else { return }
        rectangles = values
        send(["t": "icons", "vis": true, "r": rectangles])
    }

    func setPaused(_ value: Bool) {
        guard paused != value else { return }
        paused = value
        Diagnostics.shared.record("renderer.playback", "id=\(identifier) paused=\(value)")
        send(["t": "pause", "v": value])
    }

    fileprivate func receive(_ body: Any) {
        if let error = (body as? [String: Any])?["error"] as? String {
            Diagnostics.shared.record("renderer.script-error", "id=\(identifier) \(error)")
            onError?(error)
        } else if let event = (body as? [String: Any])?["event"] as? String {
            Diagnostics.shared.record("renderer.\(event)", "id=\(identifier)")
        } else if body as? String == "ready" {
            ready = true
            Diagnostics.shared.record("renderer.ready", "id=\(identifier) theme=\(theme?.id ?? "unknown")")
            send(["t": "settings", "v": parameters])
            send(["t": "icons", "vis": true, "r": rectangles])
            send(["t": "pause", "v": paused])
            onReady?()
        }
    }

    private func send(_ message: [String: Any]) {
        guard ready, let data = try? JSONSerialization.data(withJSONObject: message),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.shorelineReceive(\(json))") { [weak self] _, error in
            if let error {
                Diagnostics.shared.record("renderer.bridge-error", error.localizedDescription)
                self?.onError?(error.localizedDescription)
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let allowed = url.scheme == "shoreline" && url.host == "themes"
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("!!document.querySelector('canvas') && !!document.querySelector('canvas').getContext('webgl2')") { [weak self] value, error in
            if error != nil || value as? Bool != true {
                Diagnostics.shared.record("renderer.webgl-unavailable")
                self?.onError?("WebGL2 初始化失败，请从菜单栏重新载入壁纸。")
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Diagnostics.shared.record("renderer.navigation-error", "id=\(identifier) \(error.localizedDescription)")
        onError?(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Diagnostics.shared.record("renderer.navigation-error", "id=\(identifier) \(error.localizedDescription)")
        onError?(error.localizedDescription)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false
        Diagnostics.shared.record("renderer.web-process-terminated", "id=\(identifier) theme=\(theme?.id ?? "unknown") recovery=\(recoveryAttempts)")
        guard recoveryAttempts < 3, let theme else {
            onError?("WebKit 进程反复退出，请从菜单栏重新载入壁纸。")
            return
        }
        recoveryAttempts += 1
        load(theme: theme, parameters: parameters, reason: "web-process-recovery")
    }
}

final class WallpaperSurface {
    var screen: NSScreen
    let window: DesktopWindow
    let renderer: WallpaperRenderer

    init(screen: NSScreen, resourceURL: URL) {
        self.screen = screen
        window = DesktopWindow(screen: screen)
        renderer = WallpaperRenderer(resourceURL: resourceURL)
        window.contentView = renderer.webView
        renderer.webView.frame = CGRect(origin: .zero, size: screen.frame.size)
    }

    deinit { window.close() }
}
