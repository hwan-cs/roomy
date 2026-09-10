import SwiftUI
import AppKit

struct TreemapView: View {
    let nodes: [ScanNode]
    let onNavigate: (ScanNode) -> Void
    let onSelectForInspection: (ScanNode) -> Void
    let onClearSelection: () -> Void
    let onTrash: (ScanNode) -> Void

    let junkCategories: [URL: CategoryKind]

    init(
        nodes: [ScanNode],
        junkCategories: [URL: CategoryKind] = [:],
        onNavigate: @escaping (ScanNode) -> Void,
        onSelectForInspection: @escaping (ScanNode) -> Void = { _ in },
        onClearSelection: @escaping () -> Void = {},
        onTrash: @escaping (ScanNode) -> Void
    ) {
        self.nodes = nodes
        self.junkCategories = junkCategories
        self.onNavigate = onNavigate
        self.onSelectForInspection = onSelectForInspection
        self.onClearSelection = onClearSelection
        self.onTrash = onTrash
    }

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
            let slots = TreemapLayout.layout(items: nodes, size: { $0.size }, in: rect)

            ZStack(alignment: .topLeading) {
                TreemapCanvasLayer(slots: slots, junkCategories: junkCategories)
                    .animation(.easeOut(duration: 0.35), value: AnimatableRectVector(slots: slots))

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onClearSelection()
                    }

                ForEach(slots, id: \.item.id) { slot in
                    TreemapHitTarget(
                        node: slot.item, tileSize: slot.rect.size,
                        junkCategory: junkCategories[slot.item.url],
                        onNavigate: onNavigate, onSelectForInspection: onSelectForInspection, onTrash: onTrash
                    )
                    .frame(width: max(slot.rect.width, 0), height: max(slot.rect.height, 0))
                    .position(x: slot.rect.midX, y: slot.rect.midY)
                }
            }
        }
    }
}

private struct TreemapHitTarget: View {
    let node: ScanNode
    let tileSize: CGSize
    let junkCategory: CategoryKind?
    let onNavigate: (ScanNode) -> Void
    let onSelectForInspection: (ScanNode) -> Void
    let onTrash: (ScanNode) -> Void

    @State private var isHovering = false

    private var isProtectedRoot: Bool {
        DiskScanner.defaultRoots.contains(node.url)
    }

    private var showsOverflowButton: Bool {
        tileSize.width > 44 && tileSize.height > 34
    }

    private var showsJunkBadge: Bool {
        junkCategory != nil && min(tileSize.width, tileSize.height) > 28
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    guard node.isDirectory, !node.isMountBoundary else {
                        return
                    }
                    onNavigate(node)
                }
                .onTapGesture(count: 1) {
                    onSelectForInspection(node)
                }
                .contextMenu {
                    menuItems
                }

            if showsOverflowButton {
                Menu {
                    menuItems
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(.black.opacity(0.45)))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(5)
                .opacity(isHovering ? 1 : 0)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showsJunkBadge, let junkCategory {
                Color.clear
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .help("Detected as \(junkCategory.title) -- Roomy considers this safe to remove. \(junkCategory.explanation)")
            }
        }
        .onHover {
            isHovering = $0
        }
        .help(accessibilityLabel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(node.isDirectory && !node.isMountBoundary ? .isButton : [])
        .accessibilityHint(node.isDirectory && !node.isMountBoundary ? "Double-tap to open" : "")
    }

    @ViewBuilder
    private var menuItems: some View {
        if let junkCategory {
            Text("Detected as \(junkCategory.title)")
            Divider()
        }
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        }
        if node.isDirectory {
            Button("Open in Roomy") {
                onNavigate(node)
            }
        }
        if !isProtectedRoot, !node.isMountBoundary {
            Button("Move to Trash", role: .destructive) {
                onTrash(node)
            }
        }
    }

    private var accessibilityLabel: String {
        var parts = [node.name, ByteFormatter.string(fromByteCount: node.size)]
        if node.accessDenied {
            parts.append("access denied")
        } else if !node.isFullyScanned {
            parts.append("still scanning")
        }
        if node.isMountBoundary {
            parts.append("separate mounted volume, not scanned")
        }
        if let junkCategory {
            parts.append("detected as \(junkCategory.title)")
        }
        return parts.joined(separator: ", ")
    }
}

private struct TreemapCanvasLayer: View, @MainActor Animatable {
    var slots: [TreemapSlot<ScanNode>]
    var junkCategories: [URL: CategoryKind]

    var animatableData: AnimatableRectVector {
        get { AnimatableRectVector(slots: slots) }
        set { slots = newValue.applied(to: slots) }
    }

    var body: some View {
        Canvas { context, _ in
            for slot in slots where slot.rect.width > 0 && slot.rect.height > 0 {
                draw(slot, into: &context)
            }
        }
    }

    private func draw(_ slot: TreemapSlot<ScanNode>, into context: inout GraphicsContext) {
        let node = slot.item
        let rect = slot.rect
        let scanning = !node.isFullyScanned && !node.accessDenied
        let alpha = node.accessDenied ? 0.35 : (scanning ? 0.6 : 0.94)
        let (fill, label) = colors(for: node)

        let inset: CGFloat = 1.5
        let fillRect = rect.insetBy(dx: inset, dy: inset)
        guard fillRect.width > 0, fillRect.height > 0 else {
            return
        }
        let cornerRadius = min(7, min(fillRect.width, fillRect.height) / 4)
        let path = Path(roundedRect: fillRect, cornerRadius: cornerRadius)

        context.fill(path, with: .color(fill.opacity(alpha)))

        let strokeStyle = StrokeStyle(lineWidth: 1, dash: scanning ? [3, 2] : [])
        context.stroke(path, with: .color(.primary.opacity(0.14)), style: strokeStyle)

        drawLabel(for: node.name, size: node.size, in: fillRect, color: label, context: &context)

        if let junkCategory = junkCategories[node.url], min(fillRect.width, fillRect.height) > 28 {
            drawJunkBadge(for: junkCategory, in: fillRect, context: &context)
        }
    }

    private func drawJunkBadge(for category: CategoryKind, in rect: CGRect, context: inout GraphicsContext) {
        let diameter: CGFloat = 16
        let margin: CGFloat = 5
        let badgeRect = CGRect(x: rect.maxX - diameter - margin, y: rect.maxY - diameter - margin, width: diameter, height: diameter)
        context.fill(Path(ellipseIn: badgeRect), with: .color(.black.opacity(0.4)))
        context.fill(Path(ellipseIn: badgeRect.insetBy(dx: 1.2, dy: 1.2)), with: .color(category.tintColor))

        var checkmark = Path()
        checkmark.move(to: CGPoint(x: badgeRect.minX + badgeRect.width * 0.27, y: badgeRect.minY + badgeRect.height * 0.52))
        checkmark.addLine(to: CGPoint(x: badgeRect.minX + badgeRect.width * 0.44, y: badgeRect.minY + badgeRect.height * 0.68))
        checkmark.addLine(to: CGPoint(x: badgeRect.minX + badgeRect.width * 0.74, y: badgeRect.minY + badgeRect.height * 0.33))
        context.stroke(checkmark, with: .color(.white), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
    }

    private func drawLabel(for name: String, size: Int64, in rect: CGRect, color: Color, context: inout GraphicsContext) {
        let padding: CGFloat = 8
        let available = CGSize(width: rect.width - padding * 2, height: rect.height - padding * 2)
        guard available.width > 26, available.height > 14 else {
            return
        }

        let shortSide = min(rect.width, rect.height)
        let nameFontSize = min(15, max(10, shortSide / 7.5))
        let sizeFontSize = min(11.5, max(8.5, nameFontSize * 0.72))

        let (title, titleSize) = resolvedFittingText(
            name, font: .system(size: nameFontSize, weight: .semibold), color: color,
            availableWidth: available.width, context: &context
        )
        guard titleSize.height <= available.height else {
            return
        }

        let origin = CGPoint(x: rect.minX + padding, y: rect.minY + padding)
        context.draw(title, at: origin, anchor: .topLeading)

        let remainingHeight = available.height - titleSize.height - 2
        guard remainingHeight >= sizeFontSize else {
            return
        }

        let (sizeText, _) = resolvedFittingText(
            ByteFormatter.string(fromByteCount: size), font: .system(size: sizeFontSize), color: color.opacity(0.85),
            availableWidth: available.width, context: &context
        )
        context.draw(sizeText, at: CGPoint(x: origin.x, y: origin.y + titleSize.height + 2), anchor: .topLeading)
    }

    private func resolvedFittingText(
        _ string: String,
        font: Font,
        color: Color,
        availableWidth: CGFloat,
        context: inout GraphicsContext
    ) -> (GraphicsContext.ResolvedText, CGSize) {
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        var resolved = context.resolve(Text(string).font(font).foregroundColor(color))
        var size = resolved.measure(in: unbounded)
        guard size.width > availableWidth, string.count > 1 else {
            return (resolved, size)
        }

        let ratio = Double(availableWidth / size.width)
        var keepCount = max(1, Int(Double(string.count) * ratio) - 1)
        while keepCount > 0 {
            let truncated = String(string.prefix(keepCount)) + "..."
            resolved = context.resolve(Text(truncated).font(font).foregroundColor(color))
            size = resolved.measure(in: unbounded)
            if size.width <= availableWidth { break }
            keepCount -= 1
        }
        return (resolved, size)
    }

    private func colors(for node: ScanNode) -> (fill: Color, label: Color) {
        if node.isMountBoundary {
            return (Color(white: 0.55), .white.opacity(0.96))
        }
        let base = StableHue.paletteColor(for: node.url.path)
        let fill = Color(hue: base.hue, saturation: base.saturation, brightness: base.brightness)
        return (fill, .white.opacity(0.97))
    }
}

private struct AnimatableRectVector: VectorArithmetic {
    var values: [Double]

    init(values: [Double]) {
        self.values = values
    }

    init(slots: [TreemapSlot<ScanNode>]) {
        values = slots.flatMap { slot in
            [Double(slot.rect.origin.x), Double(slot.rect.origin.y),
             Double(slot.rect.width), Double(slot.rect.height)]
        }
    }

    func applied(to slots: [TreemapSlot<ScanNode>]) -> [TreemapSlot<ScanNode>] {
        slots.enumerated().map { index, slot in
            let base = index * 4
            guard base + 3 < values.count else {
                return slot
            }
            let rect = CGRect(x: values[base], y: values[base + 1], width: values[base + 2], height: values[base + 3])
            return TreemapSlot(item: slot.item, rect: rect)
        }
    }

    static var zero: AnimatableRectVector { AnimatableRectVector(values: []) }

    static func + (lhs: Self, rhs: Self) -> Self {
        AnimatableRectVector(values: combine(lhs.values, rhs.values, +))
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        AnimatableRectVector(values: combine(lhs.values, rhs.values, -))
    }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }

    private static func combine(_ lhs: [Double], _ rhs: [Double], _ op: (Double, Double) -> Double) -> [Double] {
        let count = max(lhs.count, rhs.count)
        return (0..<count).map { index in
            op(index < lhs.count ? lhs[index] : 0, index < rhs.count ? rhs[index] : 0)
        }
    }
}

#if DEBUG
private extension ScanNode {
    static func previewFile(_ name: String, size: Int64, scanned: Bool = true, denied: Bool = false) -> ScanNode {
        ScanNode(
            url: URL(fileURLWithPath: "/Users/preview/\(name)"),
            name: name,
            isDirectory: false,
            size: size,
            isFullyScanned: scanned,
            accessDenied: denied
        )
    }

    static func previewFolder(_ name: String, children: [ScanNode], scanned: Bool = true) -> ScanNode {
        ScanNode(
            url: URL(fileURLWithPath: "/Users/preview/\(name)", isDirectory: true),
            name: name,
            isDirectory: true,
            size: children.reduce(0) { $0 + $1.size },
            children: children,
            isFullyScanned: scanned
        )
    }

    static var previewChildren: [ScanNode] {
        [
            .previewFolder("Library", children: [.previewFile("CoreSimulator.sparsebundle", size: 40_000_000_000)]),
            .previewFolder("Downloads", children: [.previewFile("archive.zip", size: 12_000_000_000)]),
            .previewFolder("Movies", children: [.previewFile("vacation.mov", size: 8_000_000_000)], scanned: false),
            .previewFile("Applications", size: 6_000_000_000),
            .previewFile("Documents", size: 900_000_000),
            .previewFile("Pictures", size: 400_000_000),
            .previewFile("An Extraordinarily Long Folder Name That Should Never Overflow Its Cell", size: 200_000_000),
            .previewFile("Private", size: 0, denied: true),
        ]
    }

    static var previewSingle: [ScanNode] {
        [.previewFile("MacintoshHD", size: 500_000_000_000)]
    }
}

#Preview("Loaded") {
    TreemapView(nodes: ScanNode.previewChildren, onNavigate: { _ in }, onTrash: { _ in })
        .frame(width: 720, height: 480)
}

#Preview("Single Item") {
    TreemapView(nodes: ScanNode.previewSingle, onNavigate: { _ in }, onTrash: { _ in })
        .frame(width: 720, height: 480)
}

#Preview("Empty") {
    TreemapView(nodes: [], onNavigate: { _ in }, onTrash: { _ in })
        .frame(width: 720, height: 480)
}

#Preview("Dark") {
    TreemapView(nodes: ScanNode.previewChildren, onNavigate: { _ in }, onTrash: { _ in })
        .frame(width: 720, height: 480)
        .preferredColorScheme(.dark)
}

#Preview("XXL Text") {
    TreemapView(nodes: ScanNode.previewChildren, onNavigate: { _ in }, onTrash: { _ in })
        .frame(width: 720, height: 480)
        .dynamicTypeSize(.accessibility3)
}
#endif
