import Foundation
import Testing
@testable import Roomy

struct ScanNodeTests {
    private func file(_ name: String) -> ScanNode {
        ScanNode(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, isDirectory: false, size: 1)
    }

    private func folder(_ name: String, children: [ScanNode]) -> ScanNode {
        ScanNode(url: URL(fileURLWithPath: "/tmp/\(name)", isDirectory: true), name: name, isDirectory: true, children: children)
    }

    @Test func emptyDirectoryHasZeroFiles() {
        #expect(folder("empty", children: []).totalFileCount == 0)
    }

    @Test func singleFileCountsAsOne() {
        #expect(file("a.txt").totalFileCount == 1)
    }

    @Test func nestedDirectoriesSumRecursively() {
        let nested = folder("root", children: [
            file("a"),
            folder("sub", children: [file("b"), file("c")]),
            folder("emptySub", children: []),
        ])
        #expect(nested.totalFileCount == 3)
    }
}
