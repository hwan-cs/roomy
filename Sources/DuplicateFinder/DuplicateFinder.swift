import Foundation

/// **Finds duplicate files across the scanned tree**
enum DuplicateFinder {
    static func findDuplicates(in root: ScanNode) async -> [DuplicateGroup] {
        let files = collectFiles(root)
        let bySize = Dictionary(grouping: files, by: { $0.size })
        let candidateGroups = bySize.values.filter { $0.count > 1 && $0.count <= 500 }

        var groups: [DuplicateGroup] = []
        await withTaskGroup(of: [DuplicateGroup].self) { taskGroup in
            for candidates in candidateGroups {
                taskGroup.addTask {
                    await groupByContent(candidates)
                }
            }
            for await result in taskGroup {
                groups.append(contentsOf: result)
            }
        }
        return groups.sorted { $0.wastedSize > $1.wastedSize }
    }

    /// Flattens the ScanNode tree into a plain list of files.
    private static func collectFiles(_ node: ScanNode) -> [(url: URL, size: Int64)] {
        guard !node.accessDenied else {
            return []
        }
        if node.isDirectory {
            return node.children.flatMap(collectFiles)
        } else if node.size > 0 {
            return [(node.url, node.size)]
        } else {
            return []
        }
    }

    /// Compares file hash to confirm duplicates
    private static func groupByContent(_ candidates: [(url: URL, size: Int64)]) async -> [DuplicateGroup] {
        var byPartialHash: [Data: [(url: URL, size: Int64)]] = [:]
        for candidate in candidates {
            guard let partial = await FileHasher.partialHash(of: candidate.url) else {
                continue
            }
            byPartialHash[partial, default: []].append(candidate)
        }

        var result: [DuplicateGroup] = []
        for bucket in byPartialHash.values where bucket.count > 1 {
            var byFullHash: [Data: [URL]] = [:]
            for candidate in bucket {
                guard let full = await FileHasher.fullHash(of: candidate.url) else {
                    continue
                }
                byFullHash[full, default: []].append(candidate.url)
            }
            for urls in byFullHash.values where urls.count > 1 {
                result.append(DuplicateGroup(size: bucket[0].size, urls: urls.sorted { $0.path < $1.path }))
            }
        }
        return result
    }
}
