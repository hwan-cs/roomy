import Foundation

/// Recursive scan engine. Takes a URL, returns a fully-built `ScanNode` tree with real sizes, by recursively scanning every subdirectory.
enum DiskScanner {
    /// disk roots
    static let defaultRoots: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/Library"),
        URL(fileURLWithPath: "/Users"),
        URL(fileURLWithPath: "/private/var"),
        URL(fileURLWithPath: "/opt"),
        URL(fileURLWithPath: "/usr/local"),
    ]

    private static let maxReportDepth = 3
    private static let maxConcurrentDepth = 4

    static func scan(
        url: URL,
        pathFromRoot: [String] = [],
        depth: Int = 0,
        onUpdate: @escaping @Sendable (ScanNode, [String]) async -> Void,
        onBytesScanned: @escaping @Sendable (Int64) async -> Void = { _ in },
        knownDirectory: Bool = false
    ) async -> ScanNode {
        let rootStart: Date? = depth == 0 ? Date() : nil
        if depth == 0 {
            ScanLog.logger.info("Root scan started: \(url.path, privacy: .public)")
        }

        if !knownDirectory {
            guard let selfValues = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]) else {
                return ScanNode(
                    url: url,
                    isDirectory: false,
                    accessDenied: true
                )
            }

            if selfValues.isSymbolicLink == true {
                return ScanNode(
                    url: url,
                    isDirectory: false,
                    size: 0
                )
            }

            guard selfValues.isDirectory == true else {
                return ScanNode(
                    url: url,
                    isDirectory: false,
                    size: FileSystemProbe.allocatedSize(of: url)
                )
            }
        }

        let listingStart = Date()
        let listing = await FileSystemProbe.scanDirectory(at: url)
        let listingElapsed = Date().timeIntervalSince(listingStart)
        if listingElapsed > 1.0 {
            ScanLog.logger.warning("Slow listing (\(listingElapsed, format: .fixed(precision: 2))s, depth \(depth)): \(url.path, privacy: .public)")
        }

        guard let listing else {
            let denied = ScanNode(
                url: url,
                isDirectory: true,
                isFullyScanned: true,
                accessDenied: true
            )
            if depth <= maxReportDepth {
                await onUpdate(denied, pathFromRoot)
            }
            return denied
        }

        var children = listing.files

        let ownFileBytes = children.reduce(Int64(0)) { $1.isMountBoundary ? $0 : $0 + $1.size }
        await onBytesScanned(ownFileBytes)

        let directoryEntries = listing.directories

        if depth < maxConcurrentDepth {
            await withTaskGroup(of: ScanNode.self) { group in
                for directoryURL in directoryEntries {
                    group.addTask {
                        await scan(
                            url: directoryURL,
                            pathFromRoot: pathFromRoot + [directoryURL.lastPathComponent],
                            depth: depth + 1,
                            onUpdate: onUpdate,
                            onBytesScanned: onBytesScanned,
                            knownDirectory: true
                        )
                    }
                }
                for await child in group {
                    children.append(child)
                }
            }
        } else {
            for directoryURL in directoryEntries {
                let child = await scan(
                    url: directoryURL,
                    pathFromRoot: pathFromRoot + [directoryURL.lastPathComponent],
                    depth: depth + 1,
                    onUpdate: onUpdate,
                    onBytesScanned: onBytesScanned,
                    knownDirectory: true
                )
                children.append(child)
            }
        }

        children.sort { $0.size > $1.size }
        let totalSize = children.reduce(Int64(0)) { $0 + $1.size }
        let latestModification = children.compactMap(\.modificationDate).max()
        let node = ScanNode(
            url: url,
            isDirectory: true,
            size: totalSize,
            children: children,
            isFullyScanned: true,
            modificationDate: latestModification
        )
        if depth <= maxReportDepth {
            await onUpdate(node, pathFromRoot)
        }
        if depth == 0, let rootStart {
            let elapsed = Date().timeIntervalSince(rootStart)
            ScanLog.logger.info("Root scan finished (\(elapsed, format: .fixed(precision: 1))s): \(url.path, privacy: .public) size=\(ByteFormatter.string(fromByteCount: totalSize), privacy: .public)")
        }
        return node
    }
}
