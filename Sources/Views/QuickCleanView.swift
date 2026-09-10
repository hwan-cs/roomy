import SwiftUI
import AppKit

private enum QuickCleanSectionKind: Hashable {
    case category(CategoryKind)
    case leftoverAndBackups
    case appCaches
    case largeForgotten
}

private enum QuickCleanTier: CaseIterable, Hashable {
    case safe
    case worthALook

    var label: String {
        switch self {
        case .safe: 
            return "Safe to Remove"
        case .worthALook:
            return "Worth a Look"
        }
    }

    var caption: String {
        switch self {
        case .safe: 
            return "Regenerates automatically"
        case .worthALook:
            return "Weaker safety signal -- review before freeing"
        }
    }

    var color: Color {
        switch self {
        case .safe:
            return .green
        case .worthALook:
            return .orange
        }
    }
}

private struct QuickCleanPreviewItem: Identifiable {
    let name: String
    let size: Int64
    let url: URL?
    var id: String { url?.path ?? name }
}

private struct QuickCleanSection: Identifiable {
    let kind: QuickCleanSectionKind
    let tier: QuickCleanTier
    let title: String
    let explanation: String
    let systemImage: String
    let tintColor: Color
    let totalSize: Int64
    let items: [QuickCleanPreviewItem]
    var id: QuickCleanSectionKind { kind }
}

struct QuickCleanView: View {
    var scanCoordinator: ScanCoordinator
    var categoryCoordinator: CategoryCoordinator
    var quickCleanCoordinator: QuickCleanCoordinator

    private static let tint = Color(hue: 42 / 360, saturation: 0.6, brightness: 0.85)
    private static let appCacheTint = Color(hue: 205 / 360, saturation: 0.5, brightness: 0.8)
    private static let largeForgottenTint = Color(hue: 20 / 360, saturation: 0.55, brightness: 0.8)

    @State private var enabledSections: Set<QuickCleanSectionKind> = [
        .category(.cachesAndLogs), .category(.trash), .leftoverAndBackups,
        .appCaches,
    ]
    @State private var isFreeing = false
    @State private var justFreed: Int64?
    @State private var showingConfirmation = false

    var body: some View {
        let sections = computeSections()
        VStack(alignment: .leading, spacing: 0) {
            header(sections)
            
            Divider()
            
            content(sections)
        }
        .task {
            if !scanCoordinator.isScanning, let root = scanCoordinator.root {
                quickCleanCoordinator.start(scanning: root)
            }
        }
        .onChange(of: scanCoordinator.isScanning) { _, isScanning in
            if !isScanning, let root = scanCoordinator.root {
                quickCleanCoordinator.start(scanning: root)
            }
        }
    }

    private func header(_ sections: [QuickCleanSection]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                IconBadge(
                    systemImage: "wand.and.stars",
                    color: Self.tint,
                    size: 44
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Free Up Space")
                        .font(.title2.bold())
                    
                    if quickCleanCoordinator.hasDetected, !sections.isEmpty {
                        Text("\(ByteFormatter.string(fromByteCount: totalToFree(sections))) selected to free up")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if justFreed == nil, scanCoordinator.isScanning || scanCoordinator.root != nil {
                    Button(role: .destructive) {
                        showingConfirmation = true
                    } label: {
                        if isFreeing {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 140, height: 20)
                        } else if scanCoordinator.isScanning {
                            Label("Waiting for Scan...", systemImage: "sparkles")
                        } else if quickCleanCoordinator.hasDetected, !sections.isEmpty {
                            Label("Free Up \(ByteFormatter.string(fromByteCount: totalToFree(sections)))", systemImage: "sparkles")
                        } else {
                            Label("Free Up Space", systemImage: "sparkles")
                        }
                    }
                    .font(.title3.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(Self.tint)
                    .controlSize(.large)
                    .disabled(isFreeing || scanCoordinator.isScanning || !quickCleanCoordinator.hasDetected || sections.isEmpty || totalToFree(sections) == 0)
                }
            }

            if quickCleanCoordinator.hasDetected, !sections.isEmpty {
                ConfidenceBar(
                    safe: enabledTotal(in: .safe, sections),
                    worthALook: enabledTotal(in: .worthALook, sections),
                    notSelected: disabledTotal(sections)
                )
                .padding(.top, 8)
            }

            Text("Everything Roomy considers safe -- or worth a second look -- to reclaim, gathered from across your whole disk in one place.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .confirmationDialog(
            "Free up \(ByteFormatter.string(fromByteCount: totalToFree(sections)))?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Free Up \(ByteFormatter.string(fromByteCount: totalToFree(sections)))", role: .destructive) {
                Task {
                    await freeUpSpace()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This moves everything in the checked sections to the Trash. Roomy can tell you what's regenerable or already discarded, but not what's actually important to you -- review the list before confirming. This can still be undone from the Trash until it's emptied.")
        }
    }

    @ViewBuilder
    private func content(_ sections: [QuickCleanSection]) -> some View {
        if scanCoordinator.root == nil, !scanCoordinator.isScanning {
            noScanState
        } else if scanCoordinator.isScanning {
            scanningState
        } else if !quickCleanCoordinator.hasDetected {
            ProgressView("Looking for cleanup opportunities...")
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let justFreed {
            successState(freed: justFreed)
        } else if sections.isEmpty {
            ContentUnavailableView(
                "Nothing to Clean Up",
                systemImage: "checkmark.circle",
                description: Text("Roomy didn't find anything on this disk it's confident is safe to remove or worth flagging.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(QuickCleanTier.allCases, id: \.self) { tier in
                    let tierSections = self.sections(in: tier, of: sections)
                    if !tierSections.isEmpty {
                        Section {
                            ForEach(tierSections) { section in
                                QuickCleanSectionRow(
                                    section: section,
                                    isEnabled: Binding(
                                        get: { enabledSections.contains(section.kind) },
                                        set: { isOn in
                                            if isOn {
                                                enabledSections.insert(section.kind)
                                            } else {
                                                enabledSections.remove(section.kind)
                                            }
                                        }
                                    ),
                                    onDeleteItem: { item in
                                        deleteItem(item, from: section.kind)
                                    }
                                )
                            }
                        } header: {
                            TierHeader(tier: tier, totalSize: tierSections.reduce(0) { $0 + $1.totalSize })
                        }
                    }
                }
            }
        }
    }

    private var noScanState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            
            Text("Run a Full Scan First")
                .font(.title3.bold())
            
            Text("Free Up Space looks for large, forgotten items across your entire disk, not just a handful of curated folders -- it needs Storage Map's full scan to finish first so it can search everywhere safely.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            
            Button {
                scanCoordinator.start()
            } label: {
                Label("Start Scan", systemImage: "play.fill")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(Self.tint)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanningState: some View {
        VStack(spacing: 10) {
            ProgressView()
            
            Text("Scanning your whole disk...")
                .font(.callout)
            
            Text("Free Up Space will be ready once this finishes -- check Storage Map for progress.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func successState(freed: Int64) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            
            Text("Freed \(ByteFormatter.string(fromByteCount: freed))")
                .font(.title2.bold())
            
            Text("Nice work.")
                .foregroundStyle(.secondary)
            
            Button("Done") {
                justFreed = nil
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func computeSections() -> [QuickCleanSection] {
        var result: [QuickCleanSection] = []

        for kind: CategoryKind in [.cachesAndLogs, .trash] {
            guard let categoryResult = categoryCoordinator.results[kind], !categoryResult.items.isEmpty else {
                continue
            }
            result.append(QuickCleanSection(
                kind: .category(kind),
                tier: .safe,
                title: kind.title,
                explanation: kind.explanation,
                systemImage: kind.systemImage,
                tintColor: kind.tintColor,
                totalSize: categoryResult.totalSize,
                items: categoryResult.items.map { QuickCleanPreviewItem(name: $0.name, size: $0.size, url: $0.url) }
            ))
        }

        let leftoverAppData = categoryCoordinator.results[.leftoverAppData]
        let iPhoneBackups = categoryCoordinator.results[.iPhoneBackups]
        let leftoverItems = (leftoverAppData?.items ?? []) + (iPhoneBackups?.items ?? [])
        if !leftoverItems.isEmpty {
            result.append(QuickCleanSection(
                kind: .leftoverAndBackups,
                tier: .safe,
                title: "Leftover App Data & iPhone Backups",
                explanation: "Support files from apps you've already deleted, plus old iPhone/iPad backups -- both easy to forget exist at all.",
                systemImage: CategoryKind.leftoverAppData.systemImage,
                tintColor: CategoryKind.leftoverAppData.tintColor,
                totalSize: (leftoverAppData?.totalSize ?? 0) + (iPhoneBackups?.totalSize ?? 0),
                items: leftoverItems.map { QuickCleanPreviewItem(name: $0.name, size: $0.size, url: $0.url) }
            ))
        }

        if !quickCleanCoordinator.appCacheItems.isEmpty {
            result.append(QuickCleanSection(
                kind: .appCaches,
                tier: .safe,
                title: "App & Build Caches",
                explanation: "Regenerable caches found anywhere on disk -- browser caches, Steam and Adobe caches, Xcode/node_modules build caches, and similar. Apps rebuild these automatically the next time they're needed.",
                systemImage: "arrow.triangle.2.circlepath",
                tintColor: Self.appCacheTint,
                totalSize: quickCleanCoordinator.appCacheItems.reduce(0) { $0 + $1.size },
                items: quickCleanCoordinator.appCacheItems.map { QuickCleanPreviewItem(name: $0.name, size: $0.size, url: $0.url) }
            ))
        }

        if !quickCleanCoordinator.largeForgottenItems.isEmpty {
            result.append(QuickCleanSection(
                kind: .largeForgotten,
                tier: .worthALook,
                title: "Large & Forgotten Items",
                explanation: "Files and folders over 200 MB that haven't been touched in over a year, found anywhere on disk. A much weaker safety signal than the rest of this list -- worth a look before including it.",
                systemImage: "clock.badge.exclamationmark",
                tintColor: Self.largeForgottenTint,
                totalSize: quickCleanCoordinator.largeForgottenItems.reduce(0) { $0 + $1.size },
                items: quickCleanCoordinator.largeForgottenItems.map { QuickCleanPreviewItem(name: $0.name, size: $0.size, url: $0.url) }
            ))
        }

        return result
    }

    private func sections(in tier: QuickCleanTier, of sections: [QuickCleanSection]) -> [QuickCleanSection] {
        sections.filter { $0.tier == tier }
    }

    private func totalToFree(_ sections: [QuickCleanSection]) -> Int64 {
        sections.filter { enabledSections.contains($0.kind) }.reduce(0) { $0 + $1.totalSize }
    }

    private func enabledTotal(in tier: QuickCleanTier, _ sections: [QuickCleanSection]) -> Int64 {
        self.sections(in: tier, of: sections).filter { enabledSections.contains($0.kind) }.reduce(0) { $0 + $1.totalSize }
    }

    private func disabledTotal(_ sections: [QuickCleanSection]) -> Int64 {
        sections.filter { !enabledSections.contains($0.kind) }.reduce(0) { $0 + $1.totalSize }
    }

    private func freeUpSpace() async {
        isFreeing = true
        defer {
            isFreeing = false
        }

        var totalFreed: Int64 = 0
        var externallyFreed: Int64 = 0

        if enabledSections.contains(.category(.cachesAndLogs)) {
            for item in categoryCoordinator.results[.cachesAndLogs]?.items ?? [] {
                await categoryCoordinator.trash(item, in: .cachesAndLogs)
                totalFreed += item.size
            }
        }

        if enabledSections.contains(.leftoverAndBackups) {
            for kind: CategoryKind in [.leftoverAppData, .iPhoneBackups] {
                for item in categoryCoordinator.results[kind]?.items ?? [] {
                    await categoryCoordinator.trash(item, in: kind)
                    totalFreed += item.size
                }
            }
        }

        if enabledSections.contains(.category(.trash)), let trashSize = categoryCoordinator.results[.trash]?.totalSize, trashSize > 0 {
            await categoryCoordinator.emptyTrash()
            totalFreed += trashSize
        }

        if enabledSections.contains(.appCaches) {
            for item in quickCleanCoordinator.appCacheItems {
                let node = ScanNode(
                    url: item.url,
                    isDirectory: item.isDirectory,
                    size: item.size
                )
                let freed = await scanCoordinator.trash(node)
                externallyFreed += freed
                totalFreed += freed
                quickCleanCoordinator.remove(item)
            }
        }

        if enabledSections.contains(.largeForgotten) {
            for item in quickCleanCoordinator.largeForgottenItems {
                let node = ScanNode(
                    url: item.url,
                    isDirectory: item.isDirectory,
                    size: item.size
                )
                let freed = await scanCoordinator.trash(node)
                externallyFreed += freed
                totalFreed += freed
                quickCleanCoordinator.remove(item)
            }
        }

        categoryCoordinator.recordExternallyFreed(externallyFreed)
        justFreed = totalFreed
    }

    private func deleteItem(_ item: QuickCleanPreviewItem, from kind: QuickCleanSectionKind) {
        guard let url = item.url else {
            return
        }
        Task {
            switch kind {
            case .category(let categoryKind):
                if let match = categoryCoordinator.results[categoryKind]?.items.first(where: { $0.url == url }) {
                    await categoryCoordinator.trash(match, in: categoryKind)
                }
            case .leftoverAndBackups:
                if let match = categoryCoordinator.results[.leftoverAppData]?.items.first(where: { $0.url == url }) {
                    await categoryCoordinator.trash(match, in: .leftoverAppData)
                } else if let match = categoryCoordinator.results[.iPhoneBackups]?.items.first(where: { $0.url == url }) {
                    await categoryCoordinator.trash(match, in: .iPhoneBackups)
                }
            case .appCaches:
                if let match = quickCleanCoordinator.appCacheItems.first(where: { $0.url == url }) {
                    let node = ScanNode(
                        url: match.url,
                        isDirectory: match.isDirectory,
                        size: match.size
                    )
                    let freed = await scanCoordinator.trash(node)
                    categoryCoordinator.recordExternallyFreed(freed)
                    quickCleanCoordinator.remove(match)
                }
            case .largeForgotten:
                if let match = quickCleanCoordinator.largeForgottenItems.first(where: { $0.url == url }) {
                    let node = ScanNode(
                        url: match.url,
                        isDirectory: match.isDirectory,
                        size: match.size
                    )
                    let freed = await scanCoordinator.trash(node)
                    categoryCoordinator.recordExternallyFreed(freed)
                    quickCleanCoordinator.remove(match)
                }
            }
        }
    }
}

private struct ConfidenceBar: View {
    let safe: Int64
    let worthALook: Int64
    let notSelected: Int64

    private var total: Int64 {
        safe + worthALook + notSelected
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                segment(safe, label: "Safe", color: .green, totalWidth: proxy.size.width)
                segment(worthALook, label: "Worth a look", color: .orange, totalWidth: proxy.size.width)
                segment(notSelected, label: "Not selected", color: .secondary, totalWidth: proxy.size.width, dimmed: true)
            }
        }
        .frame(height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func segment(_ size: Int64, label: String, color: Color, totalWidth: CGFloat, dimmed: Bool = false) -> some View {
        if size > 0 {
            let fraction = total > 0 ? Double(size) / Double(total) : 0
            let width = max(0, totalWidth * fraction)
            Rectangle()
                .fill(dimmed ? color.opacity(0.18) : color.opacity(0.85))
                .frame(width: width)
                .overlay {
                    if width > 110 {
                        Text("\(label) · \(ByteFormatter.string(fromByteCount: size))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(dimmed ? Color.secondary : Color.white)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                    }
                }
        }
    }
}

private struct TierHeader: View {
    let tier: QuickCleanTier
    let totalSize: Int64

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tier.color)
                .frame(width: 7, height: 7)
            
            Text(tier.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tier.color)
            
            Text(tier.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(ByteFormatter.string(fromByteCount: totalSize))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct QuickCleanSectionRow: View {
    fileprivate let section: QuickCleanSection
    @Binding var isEnabled: Bool
    var onDeleteItem: (QuickCleanPreviewItem) -> Void

    @State private var expanded = false
    @State private var displayedCount = Self.pageSize
    private static let pageSize = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Toggle(isOn: $isEnabled) {
                    EmptyView()
                }
                .toggleStyle(.checkbox)
                .labelsHidden()

                IconBadge(
                    systemImage: section.systemImage,
                    color: section.tintColor
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .fontWeight(.semibold)
                    Text("\(section.items.count) item\(section.items.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(ByteFormatter.string(fromByteCount: section.totalSize))
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
            
            Text(section.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 38)

            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(section.items.prefix(displayedCount)) { item in
                        QuickCleanExpandedItemRow(
                            item: item,
                            onTrash: {
                                onDeleteItem(item)
                            }
                        )
                    }
                    if displayedCount < section.items.count {
                        Button("and \(section.items.count - displayedCount) more...") {
                            displayedCount = min(displayedCount + Self.pageSize, section.items.count)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .font(.caption)
                        .padding(.top, 2)
                    } else if section.items.count > Self.pageSize {
                        Button("Show Fewer") {
                            displayedCount = Self.pageSize
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .font(.caption)
                        .padding(.top, 2)
                    }
                }
                .padding(.leading, 38)
            }
        }
        .padding(.vertical, 8)
        .opacity(isEnabled ? 1 : 0.55)
    }
}

private struct QuickCleanExpandedItemRow: View {
    let item: QuickCleanPreviewItem
    var onTrash: () -> Void

    @State private var showingConfirmation = false

    var body: some View {
        HStack(spacing: 10) {
            if let url = item.url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "questionmark.folder")
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                if let url = item.url {
                    Text(url.deletingLastPathComponent().path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 12)

            Text(ByteFormatter.string(fromByteCount: item.size))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if let url = item.url {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Show in Finder")

                Button(role: .destructive) {
                    showingConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Move to Trash")
            }
        }
        .padding(.vertical, 2)
        .help(item.url?.path ?? item.name)
        .contextMenu {
            if let url = item.url {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Button("Move to Trash", role: .destructive) {
                    showingConfirmation = true
                }
            }
        }
        .confirmationDialog(
            "Are you sure you want to delete \"\(item.name)\"?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive, action: onTrash)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This moves it to the Trash. You can undo this from the Trash until it's emptied.")
        }
    }
}

#if DEBUG
#Preview {
    QuickCleanView(
        scanCoordinator: ScanCoordinator(),
        categoryCoordinator: CategoryCoordinator(),
        quickCleanCoordinator: QuickCleanCoordinator()
    )
}
#endif
