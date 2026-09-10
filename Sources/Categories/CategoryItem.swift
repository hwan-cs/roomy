import Foundation

/// Single row shown in a category's list
struct CategoryItem: Identifiable, Hashable, Sendable {
    let url: URL?
    let name: String
    let size: Int64
    let subtitle: String?
    let modificationDate: Date?

    var id: String { url?.path ?? name }

    init(url: URL?, name: String, size: Int64, subtitle: String? = nil, modificationDate: Date? = nil) {
        self.url = url
        self.name = name
        self.size = size
        self.subtitle = subtitle
        self.modificationDate = modificationDate
    }
}
