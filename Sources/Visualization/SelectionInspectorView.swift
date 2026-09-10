import SwiftUI

struct SelectionInspectorView: View {
    let node: ScanNode
    let junkCategory: CategoryKind?
    let isProtectedRoot: Bool
    let onReveal: () -> Void
    let onOpenInRoomy: () -> Void
    let onTrash: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            swatch

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(node.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    
                    Text("— \(detailText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text(node.url.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if node.isDirectory, !node.isMountBoundary {
                    Button("Open", action: onOpenInRoomy)
                }
                
                Button("Reveal in Finder", action: onReveal)
                
                if let junkCategory {
                    Label("Safe to clear", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(junkCategory.tintColor.opacity(0.18), in: Capsule())
                        .foregroundStyle(junkCategory.tintColor)
                        .help(junkCategory.explanation)
                }
                if node.isMountBoundary {
                    Label("Mounted volume — not scanned", systemImage: "externaldrive")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                        .help("This is a separate mounted volume, not a folder on this disk -- Roomy reports its size but doesn't walk its contents.")
                }
                if !isProtectedRoot, !node.isMountBoundary {
                    Button("Move to Trash", role: .destructive, action: onTrash)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private var detailText: String {
        let size = ByteFormatter.string(fromByteCount: node.size)
        guard node.isDirectory else {
            return size
        }
        return "\(size) · \(node.totalFileCount.formatted()) files"
    }

    private var swatch: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(junkCategory?.tintColor ?? Color.secondary.opacity(0.3))
            .frame(width: 26, height: 26)
            .overlay {
                Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundStyle(.white)
                    .font(.system(size: 12, weight: .medium))
            }
    }
}

#if DEBUG
#Preview {
    SelectionInspectorView(
        node: ScanNode(
            url: URL(fileURLWithPath: "/Users/preview/Library/Caches"), name: "Caches", isDirectory: true,
            size: 22_570_000_000,
            children: [ScanNode(url: URL(fileURLWithPath: "/Users/preview/Library/Caches/a"), name: "a", isDirectory: false, size: 1)]
        ),
        junkCategory: .cachesAndLogs,
        isProtectedRoot: false,
        onReveal: {},
        onOpenInRoomy: {},
        onTrash: {}
    )
    .frame(width: 900)
}
#endif
