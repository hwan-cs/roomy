import Foundation

/// actor-based semaphore, makes sure a scan doesn't spawn thousands of concurrent syscalls and choke the disk
actor IOConcurrencyLimiter {
    static let shared = IOConcurrencyLimiter(maxConcurrent: 48)

    private let maxConcurrent: Int
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
        available = maxConcurrent
    }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// **Filesystem access layer.**
/// `DiskScanner` and `CategoryDetector` is built on `FileSystemProbe`
enum FileSystemProbe {
    static let defaultResourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey,
        .contentModificationDateKey,
    ]

    /// Lists a directory's contents
    static func listContents(
        of url: URL,
        includingPropertiesForKeys keys: [URLResourceKey] = defaultResourceKeys,
        timeout: Duration = .seconds(2)
    ) async -> [URL]? {
        await IOConcurrencyLimiter.shared.acquire()
        let result = await withTaskGroup(of: [URL]?.self) { group -> [URL]? in
            group.addTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<[URL]?, Never>) in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let result = try? FileManager.default.contentsOfDirectory(
                            at: url,
                            includingPropertiesForKeys: keys,
                            options: []
                        )
                        continuation.resume(returning: result)
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
        await IOConcurrencyLimiter.shared.release()
        return result
    }

    static func trashItem(at url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let succeeded = (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil
                continuation.resume(returning: succeeded)
            }
        }
    }

    /// Real on-disk size for a URL
    static func allocatedSize(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]) else {
            return 0
        }
        return allocatedSize(from: values)
    }

    private static func allocatedSize(from values: URLResourceValues) -> Int64 {
        if let total = values.totalFileAllocatedSize { return Int64(total) }
        if let allocated = values.fileAllocatedSize { return Int64(allocated) }
        return Int64(values.fileSize ?? 0)
    }

    private static let scanResourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .volumeURLKey,
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey,
    ]

    private static let bootVolumeURL: URL? =
        try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeURLKey]).volume

    private static let bootVolumeTotalCapacity: Int? =
        try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey]).volumeTotalCapacity

    struct DirectoryListing: Sendable {
        var files: [ScanNode]
        var directories: [URL]
    }

    /// Lists a directory's contents, as well as their file size and subdirectories
    static func scanDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey] = scanResourceKeys,
        timeout: Duration = .seconds(2)
    ) async -> DirectoryListing? {
        await IOConcurrencyLimiter.shared.acquire()
        let result = await withTaskGroup(of: DirectoryListing?.self) { group -> DirectoryListing? in
            group.addTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<DirectoryListing?, Never>) in
                    DispatchQueue.global(qos: .userInitiated).async {
                        guard let entries = try? FileManager.default.contentsOfDirectory(
                            at: url,
                            includingPropertiesForKeys: keys,
                            options: []
                        ) else {
                            continuation.resume(returning: nil)
                            return
                        }

                        var files: [ScanNode] = []
                        files.reserveCapacity(entries.count)
                        var directories: [URL] = []
                        let keySet = Set(keys)
                        for entry in entries {
                            guard let values = try? entry.resourceValues(forKeys: keySet) else {
                                files.append(ScanNode(
                                    url: entry,
                                    isDirectory: false,
                                    accessDenied: true
                                ))
                                continue
                            }
                            if values.isSymbolicLink == true {
                                files.append(ScanNode(
                                    url: entry,
                                    isDirectory: false,
                                    size: 0
                                ))
                            } else if let bootVolumeURL, values.isDirectory == true, let volume = values.volume, volume != bootVolumeURL {
                                let total = values.volumeTotalCapacity ?? 0
                                let available = values.volumeAvailableCapacity ?? 0
                                let isBindMount = total == bootVolumeTotalCapacity
                                
                                files.append(ScanNode(
                                    url: entry,
                                    isDirectory: true,
                                    size: isBindMount ? 0 : Int64(max(0, total - available)),
                                    isFullyScanned: true,
                                    isMountBoundary: true,
                                    modificationDate: values.contentModificationDate
                                ))
                            } else if values.isDirectory == true {
                                directories.append(entry)
                            } else {
                                files.append(ScanNode(
                                    url: entry,
                                    isDirectory: false,
                                    size: allocatedSize(from: values),
                                    modificationDate: values.contentModificationDate
                                ))
                            }
                        }
                        continuation.resume(returning: DirectoryListing(files: files, directories: directories))
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
        await IOConcurrencyLimiter.shared.release()
        return result
    }
}
