import Foundation

/// Confirmed set of duplicate files
struct DuplicateGroup: Identifiable, Sendable {
    let id = UUID()
    let size: Int64
    let urls: [URL]

    var wastedSize: Int64 { size * Int64(urls.count - 1) }

    var isSafe: Bool {
        urls.allSatisfy { Self.isSafeExtension($0) && !Self.isRiskyPath($0) }
    }

    private static let safeExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp",
        "raw", "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2",
        "mov", "mp4", "m4v", "avi", "mkv", "webm", "wmv", "3gp", "flv",
        "mp3", "m4a", "wav", "aac", "flac", "aiff", "caf", "ogg",
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "pages", "numbers", "key", "txt", "rtf", "csv",
    ]

    private static func isSafeExtension(_ url: URL) -> Bool {
        safeExtensions.contains(url.pathExtension.lowercased())
    }

    private static let riskyPathPrefixes = ["/opt/", "/usr/"]

    private static let riskyPathSegments = [
        "/DerivedData/", "/CoreSimulator/", "/Library/Developer/",
        "/node_modules/", "/.git/", "/Pods/", "/site-packages/",
        "/pkgs/", "/.build/", "/venv/", "/.venv/", "/vendor/",
        "/Library/Caches/", "/Library/Mobile Documents/",
        ".app/Contents/", ".photoslibrary/", ".musiclibrary/",
        ".tvlibrary/", ".imovielibrary/", ".theater/",
        ".fcpbundle/", ".logicx/", ".garageband/",
        "/Library/Application Support/", "/Library/Containers/",
        "/Library/Group Containers/", "/Library/Frameworks/",
        "/Library/PrivateFrameworks/", "/Library/Mail/",
        "/Library/Messages/", "/Library/Calendars/",
        "/Library/Application Support/AddressBook/",
        "/Library/Application Support/MobileSync/Backup/",
        "/System/",
    ]

    private static func isRiskyPath(_ url: URL) -> Bool {
        let path = url.path
        if riskyPathPrefixes.contains(where: { path.hasPrefix($0) }) {
            return true
        }
        return riskyPathSegments.contains { path.contains($0) }
    }
}
