import SwiftUI
import AppKit

struct MainWindowView: View {
    var scanCoordinator: ScanCoordinator
    var categoryCoordinator: CategoryCoordinator
    @State private var duplicateFinderCoordinator = DuplicateFinderCoordinator()
    @State private var quickCleanCoordinator = QuickCleanCoordinator()

    @State private var selectedPath: [URL] = []
    @State private var selectedCategory: CategoryKind?
    @State private var selectedNode: ScanNode?
    @State private var showingDuplicateFinder = false
    @State private var showingQuickClean = false
    @State private var pendingTrashNode: ScanNode?

    var body: some View {
        NavigationSplitView {
            CategorySidebarView(
                coordinator: categoryCoordinator,
                totalDiskUsed: scanCoordinator.root?.size,
                selection: $selectedCategory,
                showingDuplicateFinder: $showingDuplicateFinder,
                showingQuickClean: $showingQuickClean
            )
        } detail: {
            detailContent
        }
        .frame(minWidth: 900, minHeight: 620)
        .toolbar {
            if showingDuplicateFinder {
                if duplicateFinderCoordinator.isSearching || duplicateFinderCoordinator.hasSearched {
                    ToolbarItem(placement: .status) {
                        statusLabel
                    }
                }
            } else if !showingQuickClean, scanCoordinator.isScanning || scanCoordinator.root != nil {
                ToolbarItem(placement: .status) {
                    statusLabel
                }
            }
            if categoryCoordinator.totalSpaceFreed > 0 {
                ToolbarItem(placement: .status) {
                    spaceFreedLabel
                }
            }
        }
        .task {
            categoryCoordinator.start()
        }
        .confirmationDialog(
            "Are you sure you want to delete \"\(pendingTrashNode?.name ?? "")\"?",
            isPresented: Binding(
                get: { pendingTrashNode != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingTrashNode = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let node = pendingTrashNode {
                    confirmTrash(node)
                }
                pendingTrashNode = nil
            }
            Button("Cancel", role: .cancel) {
                pendingTrashNode = nil
            }
        } message: {
            Text("This moves it to the Trash. You can undo this from the Trash until it's emptied.")
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if showingQuickClean {
            QuickCleanView(
                scanCoordinator: scanCoordinator,
                categoryCoordinator: categoryCoordinator,
                quickCleanCoordinator: quickCleanCoordinator
            )
        } else if showingDuplicateFinder {
            DuplicateFinderView(
                coordinator: duplicateFinderCoordinator,
                categoryCoordinator: categoryCoordinator,
                scanRoot: scanCoordinator.root,
                isScanning: scanCoordinator.isScanning
            )
        } else if let category = selectedCategory {
            CategoryDetailView(
                kind: category,
                result: categoryCoordinator.results[category],
                coordinator: categoryCoordinator
            )
        } else if let root = scanCoordinator.root {
            VStack(spacing: 0) {
                BreadcrumbView(
                    path: currentChain(from: root),
                    onSelect: select
                )

                Divider()

                CapacityRibbonView(
                    root: root,
                    totalDiskCapacity: categoryCoordinator.totalDiskCapacity,
                    freeSpaceNow: categoryCoordinator.freeSpaceNow,
                    totalFileCount: scanCoordinator.totalFileCount,
                    scanCompletedAt: scanCoordinator.scanCompletedAt,
                    junkCategories: categoryCoordinator.junkCategories,
                    isScanning: scanCoordinator.isScanning,
                    onRescan: rescan
                )

                Divider()

                content(for: currentChain(from: root).last ?? root)

                if let selectedNode {
                    Divider()
                    SelectionInspectorView(
                        node: selectedNode,
                        junkCategory: categoryCoordinator.junkCategories[selectedNode.url],
                        isProtectedRoot: DiskScanner.defaultRoots.contains(selectedNode.url),
                        onReveal: {
                            NSWorkspace.shared.activateFileViewerSelecting([selectedNode.url])
                        },
                        onOpenInRoomy: {
                            select(selectedNode)
                        },
                        onTrash: {
                            trash(selectedNode)
                        }
                    )
                }
            }
        } else if scanCoordinator.isScanning {
            ScanningInProgressView(
                scannedBytes: scanCoordinator.scannedBytes,
                elapsed: scanCoordinator.elapsed,
                totalDiskCapacity: categoryCoordinator.totalDiskCapacity,
                onCancel: scanCoordinator.cancel
            )
        } else {
            StartScanPromptView(totalDiskCapacity: categoryCoordinator.totalDiskCapacity) {
                scanCoordinator.start()
            }
        }
    }

    @ViewBuilder
    private func content(for node: ScanNode) -> some View {
        if node.children.isEmpty {
            if node.isFullyScanned {
                ContentUnavailableView(
                    "Nothing Here",
                    systemImage: "folder",
                    description: Text("This folder is empty.")
                )
            } else {
                ProgressView("Scanning \(node.name)...")
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if scanCoordinator.root != nil {
            TreemapView(
                nodes: node.children,
                junkCategories: categoryCoordinator.junkCategories,
                onNavigate: select,
                onSelectForInspection: selectForInspection,
                onClearSelection: clearSelection,
                onTrash: trash
            )
        }
    }

    private func trash(_ node: ScanNode) {
        pendingTrashNode = node
    }

    private func confirmTrash(_ node: ScanNode) {
        if selectedNode?.url == node.url {
            selectedNode = nil
        }
        Task {
            let freed = await scanCoordinator.trash(node)
            categoryCoordinator.recordExternallyFreed(freed)
        }
    }

    private func selectForInspection(_ node: ScanNode) {
        selectedNode = node
    }

    private func rescan() {
        selectedNode = nil
        scanCoordinator.rescan()
        categoryCoordinator.rescan()
    }

    private func clearSelection() {
        selectedNode = nil
    }

    @ViewBuilder
    private var statusLabel: some View {
        Group {
            if showingDuplicateFinder {
                duplicateFinderStatus
            } else {
                storageMapStatus
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var storageMapStatus: some View {
        HStack(spacing: 6) {
            if scanCoordinator.isScanning {
                ProgressView()
                    .controlSize(.small)
                Text(scanningStatusText)
                    .monospacedDigit()
            } else if let root = scanCoordinator.root {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(ByteFormatter.string(fromByteCount: root.size)) scanned")
            }
        }
    }

    @ViewBuilder
    private var duplicateFinderStatus: some View {
        HStack(spacing: 6) {
            if duplicateFinderCoordinator.isSearching {
                ProgressView()
                    .controlSize(.small)
                Text("Finding duplicates... \(Int(duplicateFinderCoordinator.elapsed))s")
                    .monospacedDigit()
            } else if duplicateFinderCoordinator.hasSearched {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Found duplicates in \(Int(duplicateFinderCoordinator.elapsed))s")
                    .monospacedDigit()
            }
        }
    }

    private var scanningStatusText: String {
        let scanned = ByteFormatter.string(fromByteCount: scanCoordinator.scannedBytes)
        let elapsed = "\(Int(scanCoordinator.elapsed))s"
        if let total = categoryCoordinator.totalDiskCapacity, total > 0 {
            return "\(scanned) of \(ByteFormatter.string(fromByteCount: total)) scanned... \(elapsed)"
        }
        return "\(scanned) scanned so far... \(elapsed)"
    }

    @ViewBuilder
    private var spaceFreedLabel: some View {
        if categoryCoordinator.totalSpaceFreed > 0 {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.green)
                
                Text("\(ByteFormatter.string(fromByteCount: categoryCoordinator.totalSpaceFreed)) freed")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }

    private func currentChain(from root: ScanNode) -> [ScanNode] {
        var chain = [root]
        var node = root
        for url in selectedPath {
            guard let next = node.children.first(where: { $0.url == url }) else {
                break
            }
            chain.append(next)
            node = next
        }
        return chain
    }

    private func select(_ node: ScanNode) {
        guard node.isDirectory, let root = scanCoordinator.root else {
            return
        }

        let chain = currentChain(from: root)

        if let idx = chain.firstIndex(where: { $0.url == node.url }) {
            selectedPath = idx == 0 ? [] : chain[1...idx].map(\.url)
        } else {
            selectedPath.append(node.url)
        }
        selectedNode = nil
    }
}

private struct StartScanPromptView: View {
    let totalDiskCapacity: Int64?
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 92, height: 92)
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 20, y: 10)

                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text("Map Your Storage")
                    .font(.title.weight(.bold))

                Text("Roomy scans every file on disk to show exactly where your space went.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            HStack(spacing: 22) {
                if let totalDiskCapacity {
                    ScanStat(value: ByteFormatter.string(fromByteCount: totalDiskCapacity), label: "this disk")
                    
                    Divider()
                        .frame(height: 28)
                    
                    ScanStat(value: Self.estimatedScanTime(for: totalDiskCapacity), label: "estimated time")
                    
                    Divider()
                        .frame(height: 28)
                }
                ScanStat(value: "Read-only", label: "until you confirm")
            }

            Button(action: onStart) {
                Label("Start Scan", systemImage: "play.fill")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
            .controlSize(.large)
            .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func estimatedScanTime(for capacity: Int64) -> String {
        let gb = Double(capacity) / 1_000_000_000
        switch gb {
        case ..<256:
            return "1–2 min"
        case 256..<512:
            return "2–4 min"
        case 512..<1024:
            return "4–8 min"
        case 1024..<2048:
            return "8–15 min"
        default:
            return "15+ min"
        }
    }
}

private struct ScanStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.callout.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ScanningInProgressView: View {
    let scannedBytes: Int64
    let elapsed: TimeInterval
    let totalDiskCapacity: Int64?
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 74, height: 74)
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 18, y: 8)

                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }

            VStack(spacing: 8) {
                Text("Mapping Your Mac...")
                    .font(.title.weight(.bold))

                Text(ByteFormatter.string(fromByteCount: scannedBytes))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                
                Text("scanned so far · \(Int(elapsed))s elapsed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let totalDiskCapacity, totalDiskCapacity > 0 {
                ProgressView(value: min(Double(scannedBytes), Double(totalDiskCapacity)), total: Double(totalDiskCapacity))
                    .frame(maxWidth: 280)
            } else {
                ProgressView()
                    .frame(maxWidth: 280)
            }

            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview {
    MainWindowView(scanCoordinator: ScanCoordinator(), categoryCoordinator: CategoryCoordinator())
}
#endif
