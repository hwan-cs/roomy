import Foundation
import Observation

/// `CategoryCoordinator` -  manages the 8 sidebar categories and runs their cleanup actions.
@MainActor
@Observable
final class CategoryCoordinator {
    private(set) var results: [CategoryKind: CategoryResult] = [:]
    private(set) var loadingKinds: Set<CategoryKind> = Set(CategoryKind.allCases)

    private(set) var junkCategories: [URL: CategoryKind] = [:]

    private(set) var totalSpaceFreed: Int64 = 0

    /// Real disk free space, queried directly, as a sanity check against the counter above.
    private(set) var freeSpaceBaseline: Int64?
    private(set) var freeSpaceNow: Int64?
    private(set) var totalDiskCapacity: Int64?

    var freeSpaceDelta: Int64 {
        guard let freeSpaceNow, let freeSpaceBaseline else {
            return 0
        }
        return freeSpaceNow - freeSpaceBaseline
    }

    private var scanTask: Task<Void, Never>?

    /// Runs all 8 category detectors in parallel, fills results as each finishes.
    func start() {
        guard scanTask == nil else {
            return
        }
        beginDetecting()
    }

    /// Re-runs all 8 detectors from scratch, discarding previous results.
    func rescan() {
        scanTask?.cancel()
        results = [:]
        junkCategories = [:]
        loadingKinds = Set(CategoryKind.allCases)
        beginDetecting()
    }

    private func beginDetecting() {
        let baseline = Self.currentFreeSpace()
        freeSpaceBaseline = baseline
        freeSpaceNow = baseline
        totalDiskCapacity = Self.currentTotalDiskCapacity()

        scanTask = Task {
            await withTaskGroup(of: (CategoryKind, CategoryResult).self) { group in
                for kind in CategoryKind.allCases {
                    group.addTask {
                        (kind, await CategoryDetector.detect(kind))
                    }
                }
                for await (kind, result) in group {
                    results[kind] = result
                    loadingKinds.remove(kind)
                    for item in result.items {
                        if let url = item.url {
                            junkCategories[url] = kind
                        }
                    }
                }
            }
        }
    }

    /// Lets other parts of the app add to that same counter.
    func recordExternallyFreed(_ bytes: Int64) {
        guard bytes > 0 else {
            return
        }
        totalSpaceFreed += bytes
        refreshFreeSpace()
    }

    func refreshFreeSpace() {
        freeSpaceNow = Self.currentFreeSpace()
    }

    private static func currentFreeSpace() -> Int64 {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return Int64(values?.volumeAvailableCapacity ?? 0)
    }

    private static func currentTotalDiskCapacity() -> Int64? {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey])
        return values?.volumeTotalCapacity.map(Int64.init)
    }
}

// MARK: Actual Delete actions
extension CategoryCoordinator {
    func trash(_ item: CategoryItem, in kind: CategoryKind) async {
        guard let url = item.url else {
            return
        }
        guard await FileSystemProbe.trashItem(at: url) else {
            return
        }
        guard var result = results[kind] else {
            return
        }
        result.items.removeAll { $0.id == item.id }
        result.totalSize -= item.size
        results[kind] = result
        junkCategories[url] = nil
        totalSpaceFreed += item.size
        refreshFreeSpace()
    }

    func trashAll(in kind: CategoryKind) async {
        guard let items = results[kind]?.items else {
            return
        }
        for item in items where item.url != nil {
            await trash(item, in: kind)
        }
    }

    func emptyTrash() async {
        guard let result = results[.trash] else {
            return
        }
        let freed = result.totalSize
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let script = NSAppleScript(source: "tell application \"Finder\" to empty trash")
                var error: NSDictionary?
                script?.executeAndReturnError(&error)
                continuation.resume()
            }
        }
        for item in result.items {
            if let url = item.url {
                junkCategories[url] = nil
            }
        }
        results[.trash] = CategoryResult(
            kind: .trash,
            totalSize: 0,
            items: []
        )
        totalSpaceFreed += freed
        refreshFreeSpace()
    }

    func thinTimeMachineSnapshots() async {
        let before = Self.currentFreeSpace()
        let succeeded = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
                process.arguments = ["thinlocalsnapshots", "/", "999999999999", "4"]
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
        guard succeeded else {
            return
        }
        let after = Self.currentFreeSpace()
        totalSpaceFreed += max(0, after - before)
        for item in results[.timeMachineSnapshots]?.items ?? [] {
            if let url = item.url {
                junkCategories[url] = nil
            }
        }
        results[.timeMachineSnapshots] = CategoryResult(
            kind: .timeMachineSnapshots,
            totalSize: 0,
            items: [],
            isEstimated: true
        )
        refreshFreeSpace()
    }
}
