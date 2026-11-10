import Foundation
import OSLog

final class Diagnostics {
    static let shared = Diagnostics()
    static let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Shoreline", isDirectory: true)
    private let queue = DispatchQueue(label: "local.shoreline.wallpaper.diagnostics", qos: .utility)
    private let logger = Logger(subsystem: "local.shoreline.wallpaper", category: "Lifecycle")
    private let formatter = ISO8601DateFormatter()
    private let directory: URL
    private let file: URL

    init(directory: URL = Diagnostics.directory) {
        self.directory = directory
        file = directory.appendingPathComponent("application.log")
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
    }

    func record(_ event: String, _ detail: String = "") {
        let time = Date()
        queue.async {
            let process = ProcessInfo.processInfo
            let line = "\(self.formatter.string(from: time)) pid=\(process.processIdentifier) process=\(process.processName) \(event) \(detail.prefix(4096))\n"
            self.logger.info("\(line, privacy: .public)")
            do {
                let manager = FileManager.default
                try manager.createDirectory(at: self.directory, withIntermediateDirectories: true)
                let size = (try? manager.attributesOfItem(atPath: self.file.path)[.size] as? NSNumber)?.intValue ?? 0
                if size >= 1_048_576 {
                    let previous = self.directory.appendingPathComponent("application.previous.log")
                    if manager.fileExists(atPath: previous.path) { try manager.removeItem(at: previous) }
                    try manager.moveItem(at: self.file, to: previous)
                }
                if !manager.fileExists(atPath: self.file.path) { manager.createFile(atPath: self.file.path, contents: nil) }
                let handle = try FileHandle(forWritingTo: self.file)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
            } catch { self.logger.error("Log write failed \(error.localizedDescription, privacy: .public)") }
        }
    }

    func flush() { queue.sync {} }
}
