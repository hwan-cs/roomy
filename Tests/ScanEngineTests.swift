import Foundation
import Testing
@testable import Roomy

struct ScanEngineTests {
    private func makeFixtureRoots() throws -> [URL] {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("RoomyEngineTests-\(UUID().uuidString)")
        let rootA = base.appendingPathComponent("RootA")
        let rootB = base.appendingPathComponent("RootB")
        let nested = rootA.appendingPathComponent("deep/er/nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)

        try Data(repeating: 0, count: 50_000).write(to: nested.appendingPathComponent("file.bin"))
        try Data(repeating: 0, count: 5_000).write(to: rootB.appendingPathComponent("other.bin"))

        return [rootA, rootB]
    }

    @Test func finalSnapshotContainsBothRootsFullyScanned() async throws {
        let roots = try makeFixtureRoots()
        defer {
            try? FileManager.default.removeItem(at: roots[0].deletingLastPathComponent())
        }

        let engine = ScanEngine(roots: roots)
        var last: ScanNode?
        for await snapshot in await engine.updates() {
            last = snapshot
        }

        let final = try #require(last)
        #expect(final.children.count == 2)
        #expect(final.children.allSatisfy { $0.isFullyScanned })
        #expect(final.size >= 50_000 + 5_000)
    }

    @Test func deeplyNestedUpdateCreatesPlaceholderAncestorsAndRollsSizeUp() async throws {
        let roots = try makeFixtureRoots()
        defer {
            try? FileManager.default.removeItem(at: roots[0].deletingLastPathComponent())
        }

        let engine = ScanEngine(roots: roots)
        var sawGrowingRootA = false
        var previousRootASize: Int64 = -1

        for await snapshot in await engine.updates() {
            guard let rootA = snapshot.children.first(where: { $0.name == "RootA" }) else {
                continue
            }
            if rootA.size > previousRootASize {
                sawGrowingRootA = true
                previousRootASize = rootA.size
            }
        }

        #expect(sawGrowingRootA)
        #expect(previousRootASize >= 50_000)
    }

    @Test func streamYieldsMoreThanOnce() async throws {
        let roots = try makeFixtureRoots()
        defer {
            try? FileManager.default.removeItem(at: roots[0].deletingLastPathComponent())
        }

        let engine = ScanEngine(roots: roots)
        var count = 0
        for await _ in await engine.updates() {
            count += 1
        }

        #expect(count > 1)
    }
}
