import Foundation

/// Orchestrates a full scan session across all 6 roots at once and streams a single, continuously-updating tree to the UI.
actor ScanEngine {
    private var root: ScanNode
    private var continuation: AsyncStream<ScanNode>.Continuation?
    private let roots: [URL]

    private var lastHeartbeatAt = Date.distantPast
    private var updateCount = 0

    private static let minSnapshotInterval: TimeInterval = 0.2
    private var lastYieldAt = Date.distantPast

    private(set) var scannedBytes: Int64 = 0

    init(roots: [URL] = DiskScanner.defaultRoots) {
        self.roots = roots
        root = ScanNode(
            url: URL(fileURLWithPath: "/"),
            name: "This Mac",
            isDirectory: true
        )
    }

    func updates() -> AsyncStream<ScanNode> {
        AsyncStream { continuation in
            self.continuation = continuation
            let task = Task {
                await self.run()
                self.continuation?.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run() async {
        root.children = roots
            .map { ScanNode(url: $0, isDirectory: true) }
            .sorted { $0.name < $1.name }
        continuation?.yield(root)

        await withTaskGroup(of: Void.self) { group in
            for rootURL in roots {
                group.addTask {
                    _ = await DiskScanner.scan(
                        url: rootURL,
                        pathFromRoot: [rootURL.lastPathComponent]
                    ) { node, path in
                        await self.upsert(node: node, atPath: path)
                    } onBytesScanned: { bytes in
                        await self.recordScanned(bytes: bytes)
                    }
                }
            }
        }

        continuation?.yield(root)
    }

    private func upsert(node: ScanNode, atPath path: [String]) {
        root = Self.replacing(node, in: root, atPath: path)

        let now = Date()
        guard now.timeIntervalSince(lastYieldAt) >= Self.minSnapshotInterval else {
            return
        }
        lastYieldAt = now
        continuation?.yield(root)
    }

    private func recordScanned(bytes: Int64) {
        scannedBytes += bytes
        updateCount += 1
        let now = Date()
        if now.timeIntervalSince(lastHeartbeatAt) > 2 {
            lastHeartbeatAt = now
            ScanLog.logger.info("Heartbeat: \(self.updateCount) directories scanned so far, \(ByteFormatter.string(fromByteCount: self.scannedBytes), privacy: .public) total")
        }
    }

    private static func replacing(_ newNode: ScanNode, in tree: ScanNode, atPath path: [String]) -> ScanNode {
        guard let head = path.first else {
            return newNode
        }
        let rest = Array(path.dropFirst())

        var tree = tree
        if let idx = tree.children.firstIndex(where: { $0.name == head }) {
            tree.children[idx] = rest.isEmpty ? newNode : replacing(newNode, in: tree.children[idx], atPath: rest)
        } else if rest.isEmpty {
            tree.children.append(newNode)
        } else {
            let placeholder = ScanNode(
                url: tree.url.appendingPathComponent(head),
                name: head,
                isDirectory: true
            )
            tree.children.append(replacing(newNode, in: placeholder, atPath: rest))
        }

        tree.children.sort { $0.size > $1.size }
        tree.size = tree.children.reduce(Int64(0)) { $0 + $1.size }
        return tree
    }
}
