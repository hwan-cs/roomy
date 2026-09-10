import Foundation
import Observation

@MainActor
@Observable
final class DuplicateFinderCoordinator {
    private(set) var groups: [DuplicateGroup] = []
    private(set) var isSearching = false
    private(set) var hasSearched = false
    private(set) var elapsed: TimeInterval = 0

    private var searchTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    func start(scanning root: ScanNode) {
        guard !isSearching else {
            return
        }
        isSearching = true
        hasSearched = false
        groups = []
        elapsed = 0

        let startedAt = Date()
        searchTask = Task {
            let found = await DuplicateFinder.findDuplicates(in: root)
            groups = found
            isSearching = false
            hasSearched = true
        }

        tickTask?.cancel()
        tickTask = Task {
            while !Task.isCancelled && isSearching {
                elapsed = Date().timeIntervalSince(startedAt)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @discardableResult
    func resolve(_ group: DuplicateGroup, keeping keep: URL) async -> Int64 {
        var freed: Int64 = 0
        for url in group.urls where url != keep {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }.value
                freed += group.size
            } catch {
                continue
            }
        }
        groups.removeAll { $0.id == group.id }
        return freed
    }

    @discardableResult
    func resolveAll(_ groups: [DuplicateGroup], keeping keepURL: (DuplicateGroup) -> URL?) async -> Int64 {
        var totalFreed: Int64 = 0
        for group in groups {
            guard let keep = keepURL(group) else {
                continue
            }
            totalFreed += await resolve(group, keeping: keep)
        }
        return totalFreed
    }
}
