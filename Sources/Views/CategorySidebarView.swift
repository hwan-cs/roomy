import SwiftUI

struct CategorySidebarView: View {
    var coordinator: CategoryCoordinator
    var totalDiskUsed: Int64? = nil
    @Binding var selection: CategoryKind?
    @Binding var showingDuplicateFinder: Bool
    @Binding var showingQuickClean: Bool

    private static let storageMapTint = Color(hue: 265 / 360, saturation: 0.45, brightness: 0.82)
    private static let duplicateFinderTint = Color(hue: 300 / 360, saturation: 0.45, brightness: 0.78)
    private static let quickCleanTint = Color(hue: 42 / 360, saturation: 0.6, brightness: 0.85)

    var body: some View {
        List {
            Section {
                SidebarRow(isSelected: selection == nil && !showingDuplicateFinder && !showingQuickClean) {
                    selection = nil
                    showingDuplicateFinder = false
                    showingQuickClean = false
                } label: {
                    HStack(spacing: 12) {
                        IconBadge(
                            systemImage: "square.grid.2x2",
                            color: Self.storageMapTint
                        )
                        Text("Storage Map")
                    }
                }
            }
            
            Section("Categories") {
                ForEach(CategoryKind.allCases) { kind in
                    SidebarRow(isSelected: selection == kind && !showingDuplicateFinder && !showingQuickClean) {
                        selection = kind
                        showingDuplicateFinder = false
                        showingQuickClean = false
                    } label: {
                        CategoryRow(
                            kind: kind,
                            result: coordinator.results[kind],
                            isLoading: coordinator.loadingKinds.contains(kind),
                            totalDiskUsed: totalDiskUsed
                        )
                    }
                }
            }
            
            Section("Tools") {
                SidebarRow(isSelected: showingQuickClean) {
                    selection = nil
                    showingDuplicateFinder = false
                    showingQuickClean = true
                } label: {
                    HStack(spacing: 12) {
                        IconBadge(
                            systemImage: "wand.and.stars",
                            color: Self.quickCleanTint
                        )
                        Text("Free Up Space")
                    }
                }
                
                SidebarRow(isSelected: showingDuplicateFinder) {
                    selection = nil
                    showingDuplicateFinder = true
                    showingQuickClean = false
                } label: {
                    HStack(spacing: 12) {
                        IconBadge(
                            systemImage: "doc.on.doc",
                            color: Self.duplicateFinderTint
                        )
                        Text("Find Duplicates")
                    }
                }
            }
        }
        .navigationTitle("Roomy")
        .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
        .safeAreaInset(edge: .bottom) {
            if let totalDiskCapacity = coordinator.totalDiskCapacity, let freeSpaceNow = coordinator.freeSpaceNow {
                SidebarFooter(
                    freeSpace: freeSpaceNow,
                    totalCapacity: totalDiskCapacity
                )
            }
        }
    }
}

private struct SidebarFooter: View {
    let freeSpace: Int64
    let totalCapacity: Int64

    private var usedPercent: Int {
        guard totalCapacity > 0 else {
            return 0
        }
        return Int(((1 - Double(freeSpace) / Double(totalCapacity)) * 100).rounded())
    }

    var body: some View {
        Text("\(usedPercent)% of \(ByteFormatter.string(fromByteCount: totalCapacity)) used")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }
}

struct IconBadge: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.52, weight: .medium))
                    .foregroundStyle(.white)
            }
    }
}

private struct SidebarRow<Label: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
    }
}

private struct CategoryRow: View {
    let kind: CategoryKind
    let result: CategoryResult?
    let isLoading: Bool
    let totalDiskUsed: Int64?

    private var usageFraction: Double? {
        guard let result, let totalDiskUsed, totalDiskUsed > 0 else {
            return nil
        }
        let fraction = Double(result.totalSize) / Double(totalDiskUsed)
        return fraction >= 0.005 ? fraction : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 12) {
                IconBadge(
                    systemImage: kind.systemImage,
                    color: kind.tintColor
                )

                Text(kind.title)

                Spacer()

                if isLoading {
                    Text("Scanning...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let result {
                    Text(sizeLabel(for: result))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let usageFraction {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(kind.tintColor)
                                .frame(width: proxy.size.width * usageFraction)
                        }
                }
                .frame(height: 3)
                .padding(.leading, 38)
            }
        }
    }

    private func sizeLabel(for result: CategoryResult) -> String {
        let base = ByteFormatter.string(fromByteCount: result.totalSize)
        return result.isEstimated ? "~\(base)" : base
    }
}

#if DEBUG
#Preview {
    CategorySidebarView(coordinator: CategoryCoordinator(), selection: .constant(nil), showingDuplicateFinder: .constant(false), showingQuickClean: .constant(false))
}
#endif
