import Foundation

struct ScanNode: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    var size: Int64
    var children: [ScanNode]
    var isFullyScanned: Bool
    var accessDenied: Bool
    var isMountBoundary: Bool

    let modificationDate: Date?

    var id: URL { url }

    init(
        url: URL,
        name: String? = nil,
        isDirectory: Bool,
        size: Int64 = 0,
        children: [ScanNode] = [],
        isFullyScanned: Bool = false,
        accessDenied: Bool = false,
        isMountBoundary: Bool = false,
        modificationDate: Date? = nil
    ) {
        self.url = url
        self.name = name ?? (url.pathComponents.count <= 1 ? url.path : url.lastPathComponent)
        self.isDirectory = isDirectory
        self.size = size
        self.children = children
        self.isFullyScanned = isFullyScanned
        self.accessDenied = accessDenied
        self.isMountBoundary = isMountBoundary
        self.modificationDate = modificationDate
    }
}

extension ScanNode {
    var totalFileCount: Int {
        isDirectory ? children.reduce(0) { $0 + $1.totalFileCount } : 1
    }
}
