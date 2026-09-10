import Foundation
import Testing
@testable import Roomy

struct DuplicateFinderTests {
    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RoomyDupTests-\(UUID().uuidString)")
        let sub = root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        let shared = Data("hello duplicate world".utf8)
        var sameSizeDifferentContent = Data("not the same!".utf8)
        if sameSizeDifferentContent.count < shared.count {
            sameSizeDifferentContent.append(Data(repeating: 0x2A, count: shared.count - sameSizeDifferentContent.count))
        } else {
            sameSizeDifferentContent = sameSizeDifferentContent.prefix(shared.count)
        }

        try shared.write(to: root.appendingPathComponent("a1.txt"))
        try shared.write(to: root.appendingPathComponent("a2.txt"))
        try shared.write(to: sub.appendingPathComponent("a3.txt"))
        try sameSizeDifferentContent.write(to: root.appendingPathComponent("unique.txt"))
        try Data("solo".utf8).write(to: root.appendingPathComponent("solo.txt"))

        return root
    }

    @Test func identicalContentFilesAreGroupedTogether() async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let node = await DiskScanner.scan(url: root, pathFromRoot: []) { _, _ in }
        let groups = await DuplicateFinder.findDuplicates(in: node)

        #expect(groups.count == 1)
        #expect(groups.first?.urls.count == 3)
    }

    @Test func differentContentWithMatchingSizeIsNotGrouped() async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let node = await DiskScanner.scan(url: root, pathFromRoot: []) { _, _ in }
        let groups = await DuplicateFinder.findDuplicates(in: node)

        let groupedNames = Set(groups.flatMap(\.urls).map(\.lastPathComponent))
        #expect(!groupedNames.contains("unique.txt"))
    }

    @Test func fileWithNoSizeMatchIsNeverGrouped() async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let node = await DiskScanner.scan(url: root, pathFromRoot: []) { _, _ in }
        let groups = await DuplicateFinder.findDuplicates(in: node)

        let groupedNames = Set(groups.flatMap(\.urls).map(\.lastPathComponent))
        #expect(!groupedNames.contains("solo.txt"))
    }

    @Test func wastedSizeIsSizeTimesExtraCopies() async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let node = await DiskScanner.scan(url: root, pathFromRoot: []) { _, _ in }
        let groups = await DuplicateFinder.findDuplicates(in: node)

        guard let group = groups.first else {
            Issue.record("Expected at least one duplicate group")
            return
        }
        #expect(group.wastedSize == group.size * 2)
    }
}
