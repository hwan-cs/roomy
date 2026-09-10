import Foundation

/// Finds what's actually inside each of the 8 sidebar categories.
/// Pure detection logic. `CategoryCoordinator` calls into this and owns the actions.
enum CategoryDetector {
    private static let homeURL = FileManager.default.homeDirectoryForCurrentUser

    /// Routes to function
    static func detect(_ kind: CategoryKind) async -> CategoryResult {
        switch kind {
        case .photosAndVideos:
            await detectPhotosAndVideos()
        case .messagesAndMail:
            await detectMessagesAndMail()
        case .leftoverAppData:
            await detectLeftoverAppData()
        case .iPhoneBackups:
            await detectIPhoneBackups()
        case .timeMachineSnapshots:
            await detectTimeMachineSnapshots()
        case .forgottenLargeFiles:
            await detectForgottenLargeFiles()
        case .cachesAndLogs:
            await detectCachesAndLogs()
        case .trash:
            await detectTrash()
        }
    }

    // MARK: Photos & Videos
    private static func detectPhotosAndVideos() async -> CategoryResult {
        let candidates = [
            homeURL.appendingPathComponent("Pictures/Photos Library.photoslibrary"),
            homeURL.appendingPathComponent("Movies"),
        ]
        return await sizedResult(.photosAndVideos, existingOf: candidates)
    }

    // MARK: Messages & Mail
    private static func detectMessagesAndMail() async -> CategoryResult {
        let candidates = [
            homeURL.appendingPathComponent("Library/Messages/Attachments"),
            homeURL.appendingPathComponent("Library/Mail"),
        ]
        return await sizedResult(.messagesAndMail, existingOf: candidates)
    }

    // MARK: Leftover App Data
    private static func detectLeftoverAppData() async -> CategoryResult {
        let containersURL = homeURL.appendingPathComponent("Library/Containers")
        async let installedIDs = installedBundleIDs()
        guard let entries = await FileSystemProbe.listContents(of: containersURL) else {
            return CategoryResult(kind: .leftoverAppData, totalSize: 0, items: [])
        }
        let ids = await installedIDs
        let leftovers = entries.filter {
            let name = $0.lastPathComponent
            return !name.hasPrefix("com.apple.") && !ids.contains(name)
        }
        let items = await sizedItems(for: leftovers)
        return CategoryResult(
            kind: .leftoverAppData,
            totalSize: items.reduce(0) { $0 + $1.size },
            items: items.sorted { $0.size > $1.size }
        )
    }

    private static func installedBundleIDs() async -> Set<String> {
        let appDirectories = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
        ]
        var ids: Set<String> = []
        for directory in appDirectories {
            guard let appURLs = await FileSystemProbe.listContents(of: directory) else {
                continue
            }
            for appURL in appURLs where appURL.pathExtension == "app" {
                let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
                if let data = try? Data(contentsOf: infoPlistURL),
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let bundleID = plist["CFBundleIdentifier"] as? String {
                    ids.insert(bundleID)
                }
            }
        }
        return ids
    }

    // MARK: Old iPhone/iPad Backups
    private static func detectIPhoneBackups() async -> CategoryResult {
        let backupsURL = homeURL.appendingPathComponent("Library/Application Support/MobileSync/Backup")
        guard let entries = await FileSystemProbe.listContents(of: backupsURL) else {
            return CategoryResult(kind: .iPhoneBackups, totalSize: 0, items: [])
        }
        let items = await withTaskGroup(of: CategoryItem.self) { group in
            for url in entries {
                group.addTask {
                    let node = await limitedScan(url)
                    let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    let subtitle = date.map { "Last backed up \($0.formatted(date: .abbreviated, time: .omitted))" }
                    return CategoryItem(
                        url: url,
                        name: backupDisplayName(for: url) ?? url.lastPathComponent,
                        size: node.size,
                        subtitle: subtitle,
                        modificationDate: date
                    )
                }
            }
            var results: [CategoryItem] = []
            for await item in group {
                results.append(item)
            }
            return results
        }
        return CategoryResult(
            kind: .iPhoneBackups,
            totalSize: items.reduce(0) { $0 + $1.size },
            items: items.sorted { $0.size > $1.size }
        )
    }

    private static func backupDisplayName(for url: URL) -> String? {
        let infoPlistURL = url.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return (plist["Display Name"] as? String) ?? (plist["Device Name"] as? String)
    }

    // MARK: Time Machine Snapshots
    private static func detectTimeMachineSnapshots() async -> CategoryResult {
        let rootURL = URL(fileURLWithPath: "/")
        let values = try? rootURL.resourceValues(forKeys: [
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ])
        let availableNow = Int64(values?.volumeAvailableCapacity ?? 0)
        let availableIfPurged = values?.volumeAvailableCapacityForImportantUsage ?? 0
        let dates = await snapshotDates()
        let items = dates.map { date in
            CategoryItem(
                url: nil,
                name: date.formatted(date: .abbreviated, time: .shortened),
                size: 0,
                subtitle: "Local snapshot"
            )
        }
        let estimatedSize = dates.isEmpty ? 0 : max(0, availableIfPurged - availableNow)
        return CategoryResult(
            kind: .timeMachineSnapshots,
            totalSize: estimatedSize,
            items: items,
            isEstimated: true
        )
    }

    /// **Used for Time-Machine snapshots**
    /// runs `tmutil listlocalsnapshots` / as a subprocess to get the list of local Time Machine snapshot names, then regex-extracts the timestamp (yyyy-MM-dd-HHmmss) out of each line and parses it into a Date.
    private static func snapshotDates() async -> [Date] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
                process.arguments = ["listlocalsnapshots", "/"]
                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = Pipe()

                guard (try? process.run()) != nil else {
                    continuation.resume(returning: [])
                    return
                }
                process.waitUntilExit()

                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let stampFormatter = DateFormatter()
                stampFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
                let dates = output.split(separator: "\n").compactMap { line -> Date? in
                    guard let range = line.range(of: #"\d{4}-\d{2}-\d{2}-\d{6}"#, options: .regularExpression) else {
                        return nil
                    }
                    return stampFormatter.date(from: String(line[range]))
                }
                continuation.resume(returning: dates)
            }
        }
    }

    // MARK: Forgotten Large Files
    private static func detectForgottenLargeFiles(
        minimumSize: Int64 = 100 * 1024 * 1024,
        olderThan: TimeInterval = 60 * 60 * 24 * 30 * 6
    ) async -> CategoryResult {
        let downloadsURL = homeURL.appendingPathComponent("Downloads")
        let cutoff = Date().addingTimeInterval(-olderThan)
        var items: [CategoryItem] = []

        await walk(downloadsURL) { url, isDirectory in
            guard !isDirectory else {
                return
            }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = values.contentModificationDate,
                  modDate < cutoff else {
                return
            }
            let size = FileSystemProbe.allocatedSize(of: url)
            guard size >= minimumSize else {
                return
            }
            items.append(CategoryItem(
                url: url,
                name: url.lastPathComponent,
                size: size,
                subtitle: "Last modified \(modDate.formatted(date: .abbreviated, time: .omitted))",
                modificationDate: modDate
            ))
        }

        return CategoryResult(
            kind: .forgottenLargeFiles,
            totalSize: items.reduce(0) { $0 + $1.size },
            items: items.sorted { $0.size > $1.size }
        )
    }

    /// A simple recursive directory walker. Starting from a URL, it visits every file and folder underneath it. Skips symlinks
    private static func walk(_ url: URL, depth: Int = 0, maxDepth: Int = 6, visit: (URL, Bool) -> Void) async {
        guard depth <= maxDepth else {
            return
        }
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isSymbolicLink != true else {
            return
        }
        let isDirectory = values.isDirectory == true
        visit(url, isDirectory)
        guard isDirectory else {
            return
        }
        guard let entries = await FileSystemProbe.listContents(of: url) else {
            return
        }
        for entry in entries {
            await walk(entry, depth: depth + 1, maxDepth: maxDepth, visit: visit)
        }
    }

    // MARK: Caches & Logs
    private static func detectCachesAndLogs() async -> CategoryResult {
        let candidates = [
            homeURL.appendingPathComponent("Library/Caches"),
            homeURL.appendingPathComponent("Library/Logs"),
        ]
        return await sizedResult(.cachesAndLogs, existingOf: candidates)
    }

    // MARK: Trash
    private static func detectTrash() async -> CategoryResult {
        let trashURL = homeURL.appendingPathComponent(".Trash")
        guard let entries = await FileSystemProbe.listContents(of: trashURL) else {
            return CategoryResult(kind: .trash, totalSize: 0, items: [])
        }
        let items = await sizedItems(for: entries)
        return CategoryResult(
            kind: .trash,
            totalSize: items.reduce(0) { $0 + $1.size },
            items: items.sorted { $0.size > $1.size }
        )
    }

    // MARK: Shared helpers
    private static func sizedResult(_ kind: CategoryKind, existingOf candidates: [URL]) async -> CategoryResult {
        let existing = candidates.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        let items = await sizedItems(for: existing)
        return CategoryResult(
            kind: kind,
            totalSize: items.reduce(0) { $0 + $1.size },
            items: items
        )
    }

    private static func sizedItems(for urls: [URL]) async -> [CategoryItem] {
        await withTaskGroup(of: CategoryItem.self) { group in
            for url in urls {
                group.addTask {
                    let node = await limitedScan(url)
                    let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    return CategoryItem(
                        url: url,
                        name: url.lastPathComponent,
                        size: node.size,
                        modificationDate: date
                    )
                }
            }
            var results: [CategoryItem] = []
            for await item in group {
                results.append(item)
            }
            return results
        }
    }

    private static func limitedScan(_ url: URL) async -> ScanNode {
        await ScanConcurrencyLimiter.shared.acquire()
        let node = await DiskScanner.scan(url: url, onUpdate: { _, _ in })
        await ScanConcurrencyLimiter.shared.release()
        return node
    }
}
