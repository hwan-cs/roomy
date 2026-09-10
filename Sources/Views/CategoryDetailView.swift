import SwiftUI
import AppKit

private enum ItemSortOrder: String, CaseIterable, Identifiable {
    case sizeDescending, nameAscending, dateDescending

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sizeDescending: 
            return "Size"
        case .nameAscending:
            return "Name"
        case .dateDescending:
            return "Date"
        }
    }

    func sorted(_ items: [CategoryItem]) -> [CategoryItem] {
        switch self {
        case .sizeDescending:
            items.sorted { $0.size > $1.size }
        case .nameAscending:
            items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .dateDescending:
            items.sorted { lhs, rhs in
                switch (lhs.modificationDate, rhs.modificationDate) {
                case let (l?, r?):
                    return l > r
                case (nil, nil):
                    return false
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                }
            }
        }
    }
}

struct CategoryDetailView: View {
    let kind: CategoryKind
    let result: CategoryResult?
    var coordinator: CategoryCoordinator
    
    @State private var sortOrder: ItemSortOrder = .sizeDescending
    @State private var typeFilter: FileTypeFilter?
    @State private var selectedItems: Set<CategoryItem> = []
    @State private var pendingBulkTrash = false
    @State private var pendingItemTrash: CategoryItem?
    @State private var pendingForgottenTrash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if kind == .forgottenLargeFiles, let result, !result.items.isEmpty {
                Divider()
                typeFilterChips(items: result.items)
            }
            Divider()
            if let result {
                if result.items.isEmpty {
                    ContentUnavailableView(
                        "Nothing Found",
                        systemImage: kind.systemImage,
                        description: Text("No \(kind.lowercasedNoun) found.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if kind == .forgottenLargeFiles {
                    forgottenLargeFilesList(items: sortOrder.sorted(filteredItems(result.items)))
                } else {
                    List(sortOrder.sorted(result.items)) { item in
                        CategoryItemRow(item: item, allowsTrash: kind != .trash) {
                            pendingItemTrash = item
                        }
                    }
                }
            } else {
                ProgressView("Scanning \(kind.title)...")
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: kind) {
            typeFilter = nil
            selectedItems = []
        }
        .confirmationDialog(
            kind == .trash
                ? "Are you sure you want to empty the Trash?"
                : "Are you sure you want to move all \(kind.title.lowercased()) to the Trash?",
            isPresented: $pendingBulkTrash,
            titleVisibility: .visible
        ) {
            Button(kind == .trash ? "Empty Trash" : "Move All to Trash", role: .destructive) {
                Task {
                    if kind == .trash {
                        await coordinator.emptyTrash()
                    } else {
                        await coordinator.trashAll(in: kind)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if kind == .trash {
                Text("This permanently deletes everything in the Trash. This cannot be undone.")
            } else if let result {
                Text("This moves \(result.items.count) items (\(ByteFormatter.string(fromByteCount: result.totalSize))) to the Trash. You can undo this from the Trash until it's emptied.")
            }
        }
        .confirmationDialog(
            "Are you sure you want to delete \"\(pendingItemTrash?.name ?? "")\"?",
            isPresented: Binding(
                get: { pendingItemTrash != nil },
                set: { isPresented in if !isPresented { pendingItemTrash = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let item = pendingItemTrash {
                    Task {
                        await coordinator.trash(item, in: kind)
                    }
                }
                pendingItemTrash = nil
            }
            
            Button("Cancel", role: .cancel) {
                pendingItemTrash = nil
            }
        } message: {
            Text("This moves it to the Trash. You can undo this from the Trash until it's emptied.")
        }
        .confirmationDialog(
            "Are you sure you want to move \(selectedItems.count) items to the Trash?",
            isPresented: $pendingForgottenTrash,
            titleVisibility: .visible
        ) {
            Button("Move \(selectedItems.count) to Trash", role: .destructive) {
                let items = selectedItems
                Task {
                    for item in items {
                        await coordinator.trash(item, in: kind)
                    }
                    selectedItems = []
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let totalSize = selectedItems.reduce(0) { $0 + $1.size }
            Text("This moves \(selectedItems.count) items (\(ByteFormatter.string(fromByteCount: totalSize))) to the Trash. You can undo this from the Trash until it's emptied.")
        }
    }

    private func filteredItems(_ items: [CategoryItem]) -> [CategoryItem] {
        guard let typeFilter else {
            return items
        }
        return items.filter { FileTypeFilter(item: $0) == typeFilter }
    }

    private func typeFilterChips(items: [CategoryItem]) -> some View {
        let buckets = Dictionary(grouping: items, by: FileTypeFilter.init)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(
                    label: "All \(items.count)",
                    isSelected: typeFilter == nil
                ) {
                    typeFilter = nil
                }
                ForEach(FileTypeFilter.allCases) { bucket in
                    if let count = buckets[bucket]?.count, count > 0 {
                        FilterChip(
                            label: "\(bucket.label) \(count)",
                            isSelected: typeFilter == bucket
                        ) {
                            typeFilter = typeFilter == bucket ? nil : bucket
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func forgottenLargeFilesList(items: [CategoryItem]) -> some View {
        let maxSize = items.map(\.size).max() ?? 1
        return List(items) { item in
            ForgottenFileRow(
                item: item,
                maxSize: maxSize,
                isSelected: Binding(
                    get: { selectedItems.contains(item) },
                    set: { isOn in
                        if isOn {
                            selectedItems.insert(item)
                        } else {
                            selectedItems.remove(item)
                        }
                    }
                )
            )
        }
        .safeAreaInset(edge: .bottom) {
            if !selectedItems.isEmpty {
                forgottenLargeFilesFooter
            }
        }
    }

    private var forgottenLargeFilesFooter: some View {
        let items = selectedItems
        let totalSize = items.reduce(0) { $0 + $1.size }
        return HStack {
            Text("\(items.count) selected · \(ByteFormatter.string(fromByteCount: totalSize))")
                .font(.callout)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button("Reveal in Finder") {
                let urls = items.compactMap(\.url)
                guard !urls.isEmpty else {
                    return
                }
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
            
            Button("Move \(items.count) to Trash", role: .destructive) {
                pendingForgottenTrash = true
            }
        }
        .padding()
        .background(.bar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                IconBadge(
                    systemImage: kind.systemImage,
                    color: kind.tintColor, size: 44
                )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.title2.bold())
                    if let result {
                        Text((result.isEstimated ? "~" : "") + ByteFormatter.string(fromByteCount: result.totalSize))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if let result, !result.items.isEmpty {
                    sortPicker
                }
                primaryAction
            }
            
            Text(kind.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
            
            if result?.isEstimated == true {
                Label("Size is an estimate - Time Machine snapshots don't have individually measurable sizes.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if kind == .timeMachineSnapshots {
                timeMachineSafetyNote
            }
        }
        .padding()
    }

    private var sortPicker: some View {
        PillSegmentedPicker(
            selection: $sortOrder,
            options: ItemSortOrder.allCases,
            tint: kind.tintColor
        ) { order in
            Text(order.label)
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch kind {
        case .trash:
            if let result, !result.items.isEmpty {
                Button {
                    pendingBulkTrash = true
                } label: {
                    Label("Empty Trash", systemImage: "trash.slash")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 17)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
            }
        case .timeMachineSnapshots:
            EmptyView()
        default:
            if let result, !result.items.isEmpty {
                Button {
                    pendingBulkTrash = true
                } label: {
                    Label("Move All to Trash", systemImage: "trash")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 17)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var timeMachineSafetyNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "This only removes local snapshot caches — never your actual Time Machine backups.",
                systemImage: "checkmark.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            
            Button(role: .destructive) {
                Task {
                    await coordinator.thinTimeMachineSnapshots()
                }
            } label: {
                Label("Thin Local Snapshots", systemImage: "clock.arrow.circlepath")
            }
        }
    }
}

private enum FileTypeFilter: String, CaseIterable, Identifiable {
    case video, installer, archive, doc, other

    var id: String { rawValue }

    private static let extensions: [String: FileTypeFilter] = [
        "mp4": .video, "mov": .video, "m4v": .video, "avi": .video, "mkv": .video,
        "dmg": .installer, "pkg": .installer,
        "zip": .archive, "rar": .archive, "7z": .archive, "tar": .archive, "gz": .archive, "tgz": .archive,
        "pdf": .doc, "doc": .doc, "docx": .doc, "txt": .doc, "key": .doc, "pages": .doc, "numbers": .doc, "csv": .doc, "rtf": .doc,
    ]

    init(item: CategoryItem) {
        self = Self.extensions[(item.url?.pathExtension ?? "").lowercased()] ?? .other
    }

    var label: String {
        switch self {
        case .video: 
            return "Video"
        case .installer:
            return "Installers"
        case .archive: 
            return "Archives"
        case .doc:
            return "Docs"
        case .other:
            return "Other"
        }
    }
}

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor : Color.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct SizeGutterBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.07))
                Capsule()
                    .fill(Color.accentColor.opacity(0.55))
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 6)
    }
}

private struct AgeBadge: View {
    let modificationDate: Date?

    private var years: Int {
        guard let modificationDate else {
            return 0
        }
        return Calendar.current.dateComponents([.year], from: modificationDate, to: Date()).year ?? 0
    }

    private var label: String {
        guard let modificationDate else {
            return ""
        }
        let components = Calendar.current.dateComponents([.year, .month], from: modificationDate, to: Date())
        if let year = components.year, year >= 1 {
            return "\(year) year\(year == 1 ? "" : "s") old"
        }
        let month = max(components.month ?? 0, 1)
        return "\(month) month\(month == 1 ? "" : "s") old"
    }

    private var color: Color {
        switch years {
        case 0:
            return .secondary
        case 1...4:
            return .orange
        default:
            return .red
        }
    }

    var body: some View {
        if modificationDate != nil {
            Text(label)
                .font(.caption2)
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.14), in: Capsule())
        }
    }
}

private struct ForgottenFileRow: View {
    let item: CategoryItem
    let maxSize: Int64
    @Binding var isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $isSelected) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            icon
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 12)

            AgeBadge(modificationDate: item.modificationDate)

            SizeGutterBar(fraction: maxSize > 0 ? Double(item.size) / Double(maxSize) : 0)
                .frame(width: 100)

            Text(ByteFormatter.string(fromByteCount: item.size))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .help(item.name)
        .contextMenu {
            if let url = item.url {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let url = item.url {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
        }
    }
}

private struct CategoryItemRow: View {
    let item: CategoryItem
    let allowsTrash: Bool
    var onTrash: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 26, height: 26)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            
            Spacer(minLength: 12)
            
            if item.size > 0 {
                Text(ByteFormatter.string(fromByteCount: item.size))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 64, alignment: .trailing)
            }
            
            if allowsTrash, item.url != nil {
                Button(role: .destructive, action: onTrash) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Move to Trash")
            }
        }
        .padding(.vertical, 7)
        .help(item.name)
        .contextMenu {
            categoryContextMenuContent
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let url = item.url {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var categoryContextMenuContent: some View {
        if let url = item.url {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            if allowsTrash {
                Button("Move to Trash", role: .destructive, action: onTrash)
            }
        }
    }
}

#if DEBUG
#Preview {
    CategoryDetailView(
        kind: .cachesAndLogs,
        result: CategoryResult(
            kind: .cachesAndLogs,
            totalSize: 4_200_000_000,
            items: [
                CategoryItem(url: URL(fileURLWithPath: "/tmp/Caches"), name: "Caches", size: 3_000_000_000),
                CategoryItem(url: URL(fileURLWithPath: "/tmp/Logs"), name: "Logs", size: 1_200_000_000),
            ]
        ),
        coordinator: CategoryCoordinator()
    )
}
#endif
