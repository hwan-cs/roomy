import Foundation

/// A category's detection output - kind, size, etc
struct CategoryResult: Identifiable, Sendable {
    let kind: CategoryKind
    var totalSize: Int64
    var items: [CategoryItem]
    var isEstimated: Bool = false

    var id: CategoryKind { kind }
}
