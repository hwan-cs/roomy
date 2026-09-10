import Foundation

enum QuickCleanReason: Sendable, Equatable {
    case appCache(label: String)
    case largeAndForgotten
}

struct QuickCleanItem: Identifiable, Sendable {
    let url: URL
    let name: String
    let size: Int64
    let isDirectory: Bool
    let modificationDate: Date?
    let reason: QuickCleanReason

    var id: URL { url }
}
