import Foundation
import Observation

@MainActor
@Observable
final class ScanCoordinator {
    private(set) var root: ScanNode?
    private(set) var isScanning = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var scannedBytes: Int64 = 0
    private(set) var totalFileCount: Int = 0
    private(set) var scanCompletedAt: Date?

    private var engine = ScanEngine()
    private var drainTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var backupBeforeRescan: (root: ScanNode?, scanCompletedAt: Date?, totalFileCount: Int)?

    func start() {
        guard !isScanning, root == nil else {
            return
        }
        beginScan()
    }

    func rescan() {
        guard !isScanning else {
            return
        }
        backupBeforeRescan = (root, scanCompletedAt, totalFileCount)
        root = nil
        beginScan()
    }

    private func beginScan() {
        drainTask?.cancel()
        tickTask?.cancel()
        engine = ScanEngine()
        isScanning = true
        elapsed = 0
        scannedBytes = 0
        totalFileCount = 0
        scanCompletedAt = nil

        let startedAt = Date()
        drainTask = Task {
            for await snapshot in await engine.updates() {
                if Task.isCancelled {
                    return
                }
                root = snapshot
            }
            if !Task.isCancelled {
                isScanning = false
                scanCompletedAt = Date()
                totalFileCount = root?.totalFileCount ?? 0
                backupBeforeRescan = nil
            }
        }

        let engineRef = engine
        tickTask = Task {
            while !Task.isCancelled && isScanning {
                elapsed = Date().timeIntervalSince(startedAt)
                scannedBytes = await engineRef.scannedBytes
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func cancel() {
        drainTask?.cancel()
        tickTask?.cancel()
        isScanning = false
        if let backup = backupBeforeRescan {
            root = backup.root
            scanCompletedAt = backup.scanCompletedAt
            totalFileCount = backup.totalFileCount
            backupBeforeRescan = nil
        }
    }

    @discardableResult
    func trash(_ node: ScanNode) async -> Int64 {
        guard await FileSystemProbe.trashItem(at: node.url) else {
            return 0
        }
        if let root {
            self.root = Self.removing(node.url, from: root)
        }
        return node.size
    }

    private static func removing(_ url: URL, from node: ScanNode) -> ScanNode {
        var node = node
        if let idx = node.children.firstIndex(where: { $0.url == url }) {
            node.children.remove(at: idx)
        } else if let idx = node.children.firstIndex(where: { child in
            child.isDirectory && url.path.hasPrefix(child.url.path + "/")
        }) {
            node.children[idx] = removing(url, from: node.children[idx])
        } else {
            return node
        }
        node.size = node.children.reduce(Int64(0)) { $0 + $1.size }
        return node
    }
}
