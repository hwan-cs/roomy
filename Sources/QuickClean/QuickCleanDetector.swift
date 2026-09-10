import Foundation

/// Scans the already-completed Storage Map tree to find reclaimable stuff for the "Free Up Space" feature
enum QuickCleanDetector {
    private static let knownCacheFolderNames: [String: String] = [
        "DerivedData": "Xcode Build Cache",
        "node_modules": "Node.js Packages",
        "Pods": "CocoaPods",
        ".venv": "Python Virtual Environment",
        "venv": "Python Virtual Environment",
        "__pycache__": "Python Bytecode Cache",
        ".build": "Swift Package Build Cache",
        "Cache": "App Cache",
        "Caches": "App Cache",
        "CachedData": "App Cached Data",
        "GPUCache": "Browser Graphics Cache",
        "Code Cache": "Browser Code Cache",
        "Service Worker": "Browser Site Cache",
        "PersistentCache": "Offline Media Cache",
        "Media Cache Files": "Adobe Media Cache",
        "ShaderCache": "Game Shader Cache",
        "depotcache": "Steam Download Cache",
        "appcache": "Steam App Cache",
        "Thumbnails": "Thumbnail Cache",
    ]

    private static let minimumSize: Int64 = 200 * 1024 * 1024
    private static let staleAfter: TimeInterval = 60 * 60 * 24 * 365

    static func detect(in root: ScanNode) async -> [QuickCleanItem] {
        await withTaskGroup(of: [QuickCleanItem].self) { group in
            for topLevelRoot in root.children {
                group.addTask {
                    var results: [QuickCleanItem] = []
                    walk(topLevelRoot, into: &results)
                    return results
                }
            }
            var all: [QuickCleanItem] = []
            for await partial in group {
                all.append(contentsOf: partial)
            }
            return all
        }
    }

    /// Recursive walk
    private static func walk(_ node: ScanNode, into results: inout [QuickCleanItem]) {
        let cutoff = Date().addingTimeInterval(-staleAfter)
        for child in node.children where !child.accessDenied {
            if child.isDirectory, let label = knownCacheFolderNames[child.name] {
                results.append(item(for: child, reason: .appCache(label: label)))
                continue
            }
            if child.size >= minimumSize, let modDate = child.modificationDate, modDate < cutoff {
                results.append(item(for: child, reason: .largeAndForgotten))
                continue
            }
            if child.isDirectory {
                walk(child, into: &results)
            }
        }
    }

    private static func item(for node: ScanNode, reason: QuickCleanReason) -> QuickCleanItem {
        QuickCleanItem(
            url: node.url,
            name: node.name,
            size: node.size,
            isDirectory: node.isDirectory,
            modificationDate: node.modificationDate,
            reason: reason
        )
    }
}
