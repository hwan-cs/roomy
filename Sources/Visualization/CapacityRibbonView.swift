import SwiftUI

struct CapacityRibbonView: View {
    let root: ScanNode
    let totalDiskCapacity: Int64?
    let freeSpaceNow: Int64?
    let totalFileCount: Int
    let scanCompletedAt: Date?
    let junkCategories: [URL: CategoryKind]
    var isScanning: Bool = false
    var onRescan: (() -> Void)?
    var topSegmentCount: Int = 6

    private struct RibbonSegment: Identifiable {
        let id: String
        let label: String
        let size: Int64
        let color: Color
    }

    private var segments: [RibbonSegment] {
        var result: [RibbonSegment] = []
        let topChildren = Array(root.children.prefix(topSegmentCount))
        for child in topChildren {
            let color = junkCategories[child.url]?.tintColor
                ?? StableHue.color(for: child.url.path)
            result.append(
                RibbonSegment(
                    id: child.url.path,
                    label: child.name,
                    size: child.size,
                    color: color
                )
            )
        }
        
        let other = root.children.dropFirst(topSegmentCount).reduce(Int64(0)) { $0 + $1.size }
        if other > 0 {
            result.append(
                RibbonSegment(
                    id: "__other__",
                    label: "Other",
                    size: other,
                    color: .secondary.opacity(0.4)
                )
            )
        }
        
        if let freeSpaceNow, freeSpaceNow > 0 {
            result.append(
                RibbonSegment(
                    id: "__free__",
                    label: "Free",
                    size: freeSpaceNow,
                    color: .secondary.opacity(0.22)
                )
            )
        }
        return result
    }

    private var totalForBar: Int64 {
        segments.reduce(Int64(0)) { $0 + $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            bar
            legend
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("This Mac")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            HStack(spacing: 4) {
                if let scanCompletedAt {
                    Text("Scanned")
                    
                    Text(scanCompletedAt, style: .relative)
                    
                    Text("ago ·")
                }
                Text("\(totalFileCount.formatted()) files")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let onRescan {
                Button(action: onRescan) {
                    Label("Rescan", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isScanning)
            }
        }
    }

    private var bar: some View {
        GeometryReader { proxy in
            HStack(spacing: 1.5) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: totalForBar > 0 ? proxy.size.width * (Double(segment.size) / Double(totalForBar)) : 0)
                }
            }
        }
        .frame(height: 10)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .clipShape(Capsule())
    }

    private var legend: some View {
        FlowLayout(spacing: 14) {
            ForEach(segments) { segment in
                HStack(spacing: 5) {
                    Circle()
                        .fill(segment.color)
                        .frame(width: 7, height: 7)
                    
                    Text(segment.label)
                    
                    Text(ByteFormatter.string(fromByteCount: segment.size))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > width, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: width.isFinite ? width : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#if DEBUG
#Preview {
    CapacityRibbonView(
        root: ScanNode(
            url: URL(fileURLWithPath: "/"), name: "This Mac", isDirectory: true,
            size: 500_000_000_000,
            children: [
                ScanNode(url: URL(fileURLWithPath: "/Developer"), name: "Developer", isDirectory: true, size: 271_000_000_000),
                ScanNode(url: URL(fileURLWithPath: "/Documents"), name: "Documents", isDirectory: true, size: 104_000_000_000),
                ScanNode(url: URL(fileURLWithPath: "/System"), name: "System & caches", isDirectory: true, size: 61_000_000_000),
                ScanNode(url: URL(fileURLWithPath: "/Apps"), name: "Apps", isDirectory: true, size: 24_000_000_000),
                ScanNode(url: URL(fileURLWithPath: "/Media"), name: "Media", isDirectory: true, size: 11_000_000_000),
            ]
        ),
        totalDiskCapacity: 958_000_000_000,
        freeSpaceNow: 487_000_000_000,
        totalFileCount: 1_200_000,
        scanCompletedAt: Date().addingTimeInterval(-240),
        junkCategories: [:]
    )
    .frame(width: 720)
    .padding()
}
#endif
