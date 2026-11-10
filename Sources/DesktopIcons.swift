import Cocoa
import ApplicationServices

enum IconScan {
    case permissionRequired
    case unavailable
    case found([CGRect])
}

final class DesktopIconReader {
    private let queue = DispatchQueue(label: "local.shoreline.desktop-icons", qos: .utility)
    private var busy = false

    // Run Finder IPC off the main thread. One scan at a time also bounds work when Finder is busy.
    func scan(completion: @escaping (IconScan) -> Void) {
        guard !busy else { return }
        guard AXIsProcessTrusted() else { completion(.permissionRequired); return }
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.processIdentifier else {
            completion(.unavailable)
            return
        }
        busy = true
        queue.async {
            let result = Self.read(pid: pid)
            DispatchQueue.main.async {
                self.busy = false
                completion(result)
            }
        }
    }

    private static func read(pid: pid_t) -> IconScan {
        let finder = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(finder, 0.2)
        // Finder exposes its desktop as a top-level AXScrollArea, sometimes only in AXChildren.
        // Restrict traversal to that surface so ordinary Finder windows cannot become obstacles.
        let roots = elements(finder, kAXWindowsAttribute) + elements(finder, kAXChildrenAttribute)
        let desktops = roots.filter { attribute($0, kAXRoleAttribute) as? String == kAXScrollAreaRole }
        guard !desktops.isEmpty else { return .unavailable }
        var rectangles: [CGRect] = []
        var remaining = 10000
        for desktop in desktops {
            guard attribute(desktop, "AXHidden") as? Bool != true else { continue }
            guard let children = attribute(desktop, kAXChildrenAttribute) as? [AXUIElement] else { return .unavailable }
            for child in children { collect(child, depth: 0, remaining: &remaining, into: &rectangles) }
        }
        let unique = Set(rectangles.map { RectKey($0) }).map(\.rect)
        return .found(unique.sorted { $0.minX == $1.minX ? $0.minY < $1.minY : $0.minX < $1.minX })
    }

    private static func collect(_ element: AXUIElement, depth: Int, remaining: inout Int, into rectangles: inout [CGRect]) {
        guard depth < 8, remaining > 0 else { return }
        remaining -= 1
        guard attribute(element, "AXHidden") as? Bool != true else { return }
        if attribute(element, kAXRoleAttribute) as? String == kAXImageRole {
            if let rect = frame(element), rect.width > 0, rect.height > 0 {
                rectangles.append(rect.insetBy(dx: -4, dy: -4))
            }
            return
        }
        for child in elements(element, kAXChildrenAttribute) {
            collect(child, depth: depth + 1, remaining: &remaining, into: &rectangles)
        }
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        attribute(element, name) as? [AXUIElement] ?? []
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}

private struct RectKey: Hashable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    init(_ rect: CGRect) { x = rect.minX; y = rect.minY; width = rect.width; height = rect.height }
    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct DisplayConfiguration: Equatable {
    let identifier: UInt32
    let frame: CGRect
    let scale: CGFloat

    init(identifier: UInt32, frame: CGRect, scale: CGFloat) {
        self.identifier = identifier
        self.frame = frame
        self.scale = scale
    }

    init(screen: NSScreen) {
        self.init(identifier: (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0,
                  frame: screen.frame, scale: screen.backingScaleFactor)
    }
}

enum DesktopCoordinates {
    // Accessibility uses points with a top-left origin anchored to the primary display.
    // The renderer's bridge uses physical pixels local to each screen.
    static func rectangles(_ icons: [CGRect], screen: CGRect, primaryTop: CGFloat, scale: CGFloat) -> [[Double]] {
        let screenInAX = CGRect(x: screen.minX, y: primaryTop - screen.maxY, width: screen.width, height: screen.height)
        return icons.compactMap { icon in
            let clipped = icon.intersection(screenInAX)
            guard !clipped.isNull, !clipped.isEmpty else { return nil }
            return [Double((clipped.minX - screenInAX.minX) * scale),
                    Double((clipped.minY - screenInAX.minY) * scale),
                    Double((clipped.maxX - screenInAX.minX) * scale),
                    Double((clipped.maxY - screenInAX.minY) * scale)]
        }
    }
}
