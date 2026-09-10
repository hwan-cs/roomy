import SwiftUI
import AppKit

private enum DuplicateFilter: String, CaseIterable, Identifiable {
    case safeOnly
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .safeOnly:
            return "Safe Only"
        case .all:
            return "All Duplicates"
        }
    }
}

private enum DuplicateKeepStrategy: String, CaseIterable, Identifiable {
    case newest
    case shortestPath
    case manual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest: 
            return "Keep Newest"
        case .shortestPath:
            return "Keep Shortest Path"
        case .manual:
            return "Manual"
        }
    }

    var captionNoun: String {
        switch self {
        case .newest: 
            return "newest copy"
        case .shortestPath:
            return "copy in the shortest path"
        case .manual:
            return "copy you pick"
        }
    }

    var qualifier: String {
        switch self {
        case .newest: 
            return "newest"
        case .shortestPath:
            return "shortest path"
        case .manual:
            return "kept manually"
        }
    }
}

struct DuplicateFinderView: View {
    var coordinator: DuplicateFinderCoordinator
    var categoryCoordinator: CategoryCoordinator
    var scanRoot: ScanNode?
    var isScanning: Bool

    private static let accentTint = Color(hue: 300 / 360, saturation: 0.45, brightness: 0.78)

    @State private var filter: DuplicateFilter = .safeOnly
    @State private var strategy: DuplicateKeepStrategy = .newest
    @State private var manualOverrides: [DuplicateGroup.ID: URL] = [:]
    @State private var filtered: [DuplicateGroup] = []
    @State private var displayedCount = Self.pageSize
    private static let pageSize = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(filtered)
            Divider()
            content(filtered)
        }
        .onChange(of: filter) { _, _ in
            recomputeFiltered()
        }
        .onChange(of: coordinator.groups.count) { _, _ in
            recomputeFiltered()
        }
        .onAppear {
            recomputeFiltered()
        }
    }

    private func recomputeFiltered() {
        switch filter {
        case .safeOnly:
            filtered = coordinator.groups.filter(\.isSafe)
        case .all:
            filtered = coordinator.groups
        }
        displayedCount = Self.pageSize
    }

    private func keepURL(for group: DuplicateGroup) -> URL? {
        if let override = manualOverrides[group.id] {
            return override
        }
        switch strategy {
        case .newest:
            return group.urls.max { lhs, rhs in
                modificationDate(lhs) ?? .distantPast < modificationDate(rhs) ?? .distantPast
            } ?? group.urls.first
        case .shortestPath:
            return group.urls.min { $0.path.count < $1.path.count } ?? group.urls.first
        case .manual:
            return nil
        }
    }

    private func removableCount(_ groups: [DuplicateGroup]) -> Int {
        groups.reduce(0) { total, group in
            keepURL(for: group) != nil ? total + (group.urls.count - 1) : total
        }
    }

    private func removableSize(_ groups: [DuplicateGroup]) -> Int64 {
        groups.reduce(0) { total, group in
            keepURL(for: group) != nil ? total + group.wastedSize : total
        }
    }

    private func header(_ filtered: [DuplicateGroup]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                IconBadge(
                    systemImage: "doc.on.doc",
                    color: Self.accentTint,
                    size: 44
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Duplicate Files")
                        .font(.title2.bold())

                    if coordinator.hasSearched {
                        Text("\(ByteFormatter.string(fromByteCount: totalWasted(filtered))) reclaimable across \(filtered.count) sets")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if coordinator.hasSearched, !coordinator.groups.isEmpty {
                    filterPicker
                }
            }

            if coordinator.hasSearched, !filtered.isEmpty {
                strategyRow(filtered)
            }

            Text("Exact-content duplicates anywhere already scanned.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if filter == .safeOnly {
                Label("Showing only everyday photos, videos, audio, and documents found outside build/cache/system locations — safe to trash without checking each one.", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func strategyRow(_ filtered: [DuplicateGroup]) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ByteFormatter.string(fromByteCount: removableSize(filtered)))
                    .font(.title.weight(.bold))
                    .monospacedDigit()
                Text("reclaimable — Roomy keeps the \(strategy.captionNoun) in its original folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            PillSegmentedPicker(
                selection: $strategy,
                options: DuplicateKeepStrategy.allCases,
                tint: Self.accentTint
            ) { option in
                Text(option.label)
            }

            let count = removableCount(filtered)
            Button(role: .destructive) {
                Task {
                    let freed = await coordinator.resolveAll(filtered, keeping: keepURL)
                    categoryCoordinator.recordExternallyFreed(freed)
                    manualOverrides = [:]
                }
            } label: {
                Label("Remove \(count) \(count == 1 ? "Copy" : "Copies")", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .disabled(count == 0)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private var filterPicker: some View {
        PillSegmentedPicker(
            selection: $filter,
            options: DuplicateFilter.allCases,
            tint: Self.accentTint
        ) { option in
            Text(option.label)
        }
    }

    private func totalWasted(_ groups: [DuplicateGroup]) -> Int64 {
        groups.reduce(0) { $0 + $1.wastedSize }
    }

    @ViewBuilder
    private func content(_ filtered: [DuplicateGroup]) -> some View {
        if coordinator.isSearching {
            ProgressView("Looking for duplicates...")
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !coordinator.hasSearched {
            startPrompt
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if coordinator.groups.isEmpty {
            ContentUnavailableView(
                "No Duplicates Found",
                systemImage: "checkmark.circle",
                description: Text("Nothing exactly duplicated was found in your scanned files.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            ContentUnavailableView(
                "No Safe Duplicates Found",
                systemImage: "checkmark.circle",
                description: Text("\(coordinator.groups.count) duplicate sets were found, but none were considered safe to delete. Switch to \"All Duplicates\" to see them.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(filtered.prefix(displayedCount)) { group in
                    DuplicateGroupSection(
                        group: group,
                        keepURL: keepURL(for: group),
                        qualifier: manualOverrides[group.id] != nil ? "kept manually" : strategy.qualifier,
                        onPick: { url in
                            manualOverrides[group.id] = url
                        }
                    )
                }
                if displayedCount < filtered.count {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .onAppear {
                        displayedCount = min(displayedCount + Self.pageSize, filtered.count)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var startPrompt: some View {
        if isScanning {
            VStack(spacing: 8) {
                ProgressView()
                Text("Waiting for the initial scan to finish...")
                    .foregroundStyle(.secondary)
            }
        } else {
            Button {
                if let scanRoot {
                    coordinator.start(scanning: scanRoot)
                }
            } label: {
                Label("Find Duplicates", systemImage: "doc.on.doc")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(Self.accentTint)
            .controlSize(.large)
            .disabled(scanRoot == nil)
        }
    }
}

private func modificationDate(_ url: URL) -> Date? {
    try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
}

private struct DuplicateGroupSection: View {
    let group: DuplicateGroup
    let keepURL: URL?
    let qualifier: String
    var onPick: (URL) -> Void

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: group.urls.first?.path ?? ""))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(group.urls.first?.lastPathComponent ?? "")
                        .fontWeight(.semibold)
                    
                    Text("\(group.urls.count) identical copies · \(ByteFormatter.string(fromByteCount: group.size)) each")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(ByteFormatter.string(fromByteCount: group.wastedSize))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button {
                    expanded.toggle()
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(group.urls, id: \.self) { url in
                        DuplicateURLRow(
                            url: url,
                            isKeep: url == keepURL,
                            qualifier: qualifier
                        ) {
                            onPick(url)
                        }
                    }
                }
                .padding(.leading, 36)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct DuplicateURLRow: View {
    let url: URL
    let isKeep: Bool
    let qualifier: String
    var onPick: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if isKeep {
                Text("KEEP")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.16), in: Capsule())
            } else {
                Button(action: onPick) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Keep this copy instead")
            }

            Text(url.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            if isKeep {
                Text(qualifier)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let date = modificationDate(url) {
                Text(date.formatted(.dateTime.month().year()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isKeep {
                onPick()
            }
        }
        .help(url.path)
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            if !isKeep {
                Button("Keep This One", action: onPick)
            }
        }
    }
}

#if DEBUG
#Preview {
    DuplicateFinderView(
        coordinator: DuplicateFinderCoordinator(),
        categoryCoordinator: CategoryCoordinator(),
        scanRoot: nil,
        isScanning: false
    )
}
#endif
