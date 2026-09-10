import Foundation
import Testing
@testable import Roomy

struct QuickCleanDetectorTests {
    private static let staleDate = Date().addingTimeInterval(-60 * 60 * 24 * 400)
    private static let recentDate = Date().addingTimeInterval(-60 * 60 * 24 * 10)

    private func syntheticRoot(containing scanRoot: ScanNode) -> ScanNode {
        ScanNode(
            url: URL(fileURLWithPath: "/"),
            name: "This Mac",
            isDirectory: true,
            children: [scanRoot]
        )
    }

    @Test func devCacheFolderIsClaimedAndNotRecursedInto() async {
        let root = URL(fileURLWithPath: "/tmp/quickclean-devcache")
        let huge = ScanNode(url: root.appendingPathComponent("MyProject/node_modules/huge.bin"), name: "huge.bin", isDirectory: false, size: 500_000_000)
        let nodeModules = ScanNode(url: root.appendingPathComponent("MyProject/node_modules"), name: "node_modules", isDirectory: true, size: 500_000_000, children: [huge], isFullyScanned: true)
        let project = ScanNode(url: root.appendingPathComponent("MyProject"), name: "MyProject", isDirectory: true, size: 500_000_000, children: [nodeModules], isFullyScanned: true)
        let scanRoot = ScanNode(url: root, name: "root", isDirectory: true, size: 500_000_000, children: [project], isFullyScanned: true)

        let items = await QuickCleanDetector.detect(in: syntheticRoot(containing: scanRoot))

        #expect(items.count == 1)
        #expect(items.first?.name == "node_modules")
        guard case let .appCache(label) = items.first?.reason else {
            Issue.record("expected an .appCache reason")
            return
        }
        #expect(label == "Node.js Packages")
    }

    @Test func largeStaleFolderIsClaimed() async {
        let root = URL(fileURLWithPath: "/tmp/quickclean-large-stale")
        let asset = ScanNode(url: root.appendingPathComponent("OldProject/asset.bin"), name: "asset.bin", isDirectory: false, size: 300_000_000, modificationDate: Self.staleDate)
        let oldProject = ScanNode(url: root.appendingPathComponent("OldProject"), name: "OldProject", isDirectory: true, size: 300_000_000, children: [asset], isFullyScanned: true, modificationDate: Self.staleDate)
        let scanRoot = ScanNode(url: root, name: "root", isDirectory: true, size: 300_000_000, children: [oldProject], isFullyScanned: true)

        let items = await QuickCleanDetector.detect(in: syntheticRoot(containing: scanRoot))

        #expect(items.count == 1)
        #expect(items.first?.name == "OldProject")
        #expect(items.first?.reason == .largeAndForgotten)
    }

    @Test func largeButRecentFolderIsNotClaimed() async {
        let root = URL(fileURLWithPath: "/tmp/quickclean-large-recent")
        let asset = ScanNode(url: root.appendingPathComponent("ActiveProject/asset.bin"), name: "asset.bin", isDirectory: false, size: 300_000_000, modificationDate: Self.recentDate)
        let activeProject = ScanNode(url: root.appendingPathComponent("ActiveProject"), name: "ActiveProject", isDirectory: true, size: 300_000_000, children: [asset], isFullyScanned: true, modificationDate: Self.recentDate)
        let scanRoot = ScanNode(url: root, name: "root", isDirectory: true, size: 300_000_000, children: [activeProject], isFullyScanned: true)

        let items = await QuickCleanDetector.detect(in: syntheticRoot(containing: scanRoot))

        #expect(items.isEmpty)
    }

    @Test func smallStaleFolderIsNotClaimed() async {
        let root = URL(fileURLWithPath: "/tmp/quickclean-small-stale")
        let note = ScanNode(url: root.appendingPathComponent("TinyOldFolder/note.txt"), name: "note.txt", isDirectory: false, size: 1_000, modificationDate: Self.staleDate)
        let tinyFolder = ScanNode(url: root.appendingPathComponent("TinyOldFolder"), name: "TinyOldFolder", isDirectory: true, size: 1_000, children: [note], isFullyScanned: true, modificationDate: Self.staleDate)
        let scanRoot = ScanNode(url: root, name: "root", isDirectory: true, size: 1_000, children: [tinyFolder], isFullyScanned: true)

        let items = await QuickCleanDetector.detect(in: syntheticRoot(containing: scanRoot))

        #expect(items.isEmpty)
    }

    @Test func nestedDevCacheIsNotDoubleClaimed() async {
        let root = URL(fileURLWithPath: "/tmp/quickclean-nested-devcache")
        let innerPods = ScanNode(url: root.appendingPathComponent("App/DerivedData/Pods"), name: "Pods", isDirectory: true, size: 50_000_000, isFullyScanned: true)
        let derivedData = ScanNode(url: root.appendingPathComponent("App/DerivedData"), name: "DerivedData", isDirectory: true, size: 500_000_000, children: [innerPods], isFullyScanned: true)
        let app = ScanNode(url: root.appendingPathComponent("App"), name: "App", isDirectory: true, size: 500_000_000, children: [derivedData], isFullyScanned: true)
        let scanRoot = ScanNode(url: root, name: "root", isDirectory: true, size: 500_000_000, children: [app], isFullyScanned: true)

        let items = await QuickCleanDetector.detect(in: syntheticRoot(containing: scanRoot))

        #expect(items.count == 1)
        #expect(items.first?.name == "DerivedData")
    }

    @Test func topLevelRootItselfIsNeverClaimed() async {
        let root = URL(fileURLWithPath: "/tmp/quickclean-root-guard")
        let scanRoot = ScanNode(url: root, name: "root", isDirectory: true, size: 900_000_000, isFullyScanned: true, modificationDate: Self.staleDate)

        let items = await QuickCleanDetector.detect(in: syntheticRoot(containing: scanRoot))

        #expect(items.isEmpty)
    }
}
