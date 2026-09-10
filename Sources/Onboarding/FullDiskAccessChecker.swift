import AppKit
import Foundation

/// Checks whether the app has Full Disk Access granted, since macOS doesn't expose a direct API for this.
/// **It infers it by trying to actually read protected folders. Like Mail and Safari in this case :D**
enum FullDiskAccessChecker {
    private static var probePaths: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Mail"),
            home.appendingPathComponent("Library/Safari"),
        ]
    }

    static func currentStatus() -> Bool {
        let fm = FileManager.default
        var sawExistingPath = false

        for path in probePaths {
            guard fm.fileExists(atPath: path.path) else {
                continue
            }
            sawExistingPath = true
            if (try? fm.contentsOfDirectory(atPath: path.path)) != nil {
                return true
            }
        }

        return !sawExistingPath
    }

    static func statusUpdates(pollInterval: Duration = .seconds(1)) -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .utility) {
                var lastStatus: Bool?
                while !Task.isCancelled {
                    let status = currentStatus()
                    if status != lastStatus {
                        lastStatus = status
                        continuation.yield(status)
                    }
                    if status {
                        continuation.finish()
                        return
                    }
                    try? await Task.sleep(for: pollInterval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    @MainActor
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
