import Foundation
import Testing
@testable import Roomy

struct DiskScannerTests {
    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RoomyTests-\(UUID().uuidString)")
        let sub = root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        try Data(repeating: 0, count: 100_000).write(to: root.appendingPathComponent("big.bin"))
        try Data(repeating: 0, count: 1).write(to: root.appendingPathComponent("small.bin"))
        try Data(repeating: 0, count: 10_000).write(to: sub.appendingPathComponent("nested.bin"))

        try? FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("loop"),
            withDestinationURL: root
        )

        return root
    }

    @Test func scanAggregatesSizesAndSortsLargestFirst() async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let node = await DiskScanner.scan(url: root, pathFromRoot: []) { _, _ in }

        #expect(node.isDirectory)
        #expect(node.isFullyScanned)
        #expect(node.children.first?.name == "big.bin")
        #expect(node.size >= 100_000 + 10_000)
    }

    @Test func symlinksAreNotFollowed() async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let node = await DiskScanner.scan(url: root, pathFromRoot: []) { _, _ in }

        let loop = node.children.first { $0.name == "loop" }
        #expect(loop != nil)
        #expect(loop?.isDirectory == false)
        #expect(loop?.children.isEmpty == true)
    }

    @Test func nestedDirectorySizeRollsUpToParent() async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let node = await DiskScanner.scan(url: root, pathFromRoot: []) { _, _ in }

        let sub = node.children.first { $0.name == "sub" }
        #expect(sub?.isDirectory == true)
        #expect((sub?.size ?? 0) >= 10_000)
    }

    @Test func unreadableDirectoryIsReportedAsAccessDenied() async throws {
        let root = try makeFixture()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("locked").path)
            try? FileManager.default.removeItem(at: root)
        }

        let locked = root.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)

        let node = await DiskScanner.scan(url: root, pathFromRoot: []) { _, _ in }
        let lockedNode = node.children.first { $0.name == "locked" }

        #expect(lockedNode?.accessDenied == true)
    }

    @Test func reportsUpdatesForEveryCompletedDirectoryNotJustTheRoot() async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        var reportedPaths: [[String]] = []
        _ = await DiskScanner.scan(url: root, pathFromRoot: ["root"]) { _, path in
            reportedPaths.append(path)
        }

        #expect(reportedPaths.contains(["root", "sub"]))
        #expect(reportedPaths.contains(["root"]))
    }
}
