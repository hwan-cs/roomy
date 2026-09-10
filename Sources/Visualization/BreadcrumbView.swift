import SwiftUI

struct BreadcrumbView: View {
    let path: [ScanNode]
    let onSelect: (ScanNode) -> Void

    init(path: [ScanNode], onSelect: @escaping (ScanNode) -> Void) {
        self.path = path
        self.onSelect = onSelect
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(path.enumerated()), id: \.element.id) { index, node in
                    let isCurrent = index == path.count - 1

                    Button {
                        onSelect(node)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: index == 0 ? "internaldrive" : "folder.fill")
                                .symbolRenderingMode(.hierarchical)
                                .imageScale(.small)
                                .accessibilityHidden(true)
                            
                            Text(node.name)
                                .font(.subheadline)
                                .fontWeight(isCurrent ? .semibold : .regular)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
                    .disabled(isCurrent)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                    .accessibilityHint(isCurrent ? "" : "Double-tap to go to \(node.name)")

                    if !isCurrent {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
private extension ScanNode {
    static func previewFolder(_ name: String) -> ScanNode {
        ScanNode(url: URL(fileURLWithPath: "/preview/\(name)", isDirectory: true), name: name, isDirectory: true)
    }
}

private extension [ScanNode] {
    static var previewPath: [ScanNode] {
        [.previewFolder("Macintosh HD"), .previewFolder("Users"), .previewFolder("yourname"), .previewFolder("Library")]
    }

    static var previewDeepPath: [ScanNode] {
        previewPath + [.previewFolder("Application Support"), .previewFolder("com.example.SomeReallyLongBundleIdentifier")]
    }
}

#Preview("Typical") {
    BreadcrumbView(path: .previewPath, onSelect: { _ in })
        .frame(width: 480)
}

#Preview("Root Only") {
    BreadcrumbView(path: [.previewFolder("Macintosh HD")], onSelect: { _ in })
        .frame(width: 480)
}

#Preview("Deep / Overflow") {
    BreadcrumbView(path: .previewDeepPath, onSelect: { _ in })
        .frame(width: 320)
}

#Preview("Dark") {
    BreadcrumbView(path: .previewPath, onSelect: { _ in })
        .frame(width: 480)
        .preferredColorScheme(.dark)
}

#Preview("XXL Text") {
    BreadcrumbView(path: .previewPath, onSelect: { _ in })
        .frame(width: 480)
        .dynamicTypeSize(.accessibility3)
}
#endif
