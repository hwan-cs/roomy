import SwiftUI
import AppKit

struct MenuBarExtraLabelView: View {
    var categoryCoordinator: CategoryCoordinator

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "internaldrive")
            if let free = categoryCoordinator.freeSpaceNow {
                Text(ByteFormatter.string(fromByteCount: free))
            }
        }
        .task {
            while !Task.isCancelled {
                categoryCoordinator.refreshFreeSpace()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}

struct MenuBarExtraContentView: View {
    var categoryCoordinator: CategoryCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let free = categoryCoordinator.freeSpaceNow {
                Text("\(ByteFormatter.string(fromByteCount: free)) free")
            }
            if categoryCoordinator.totalSpaceFreed > 0 {
                Text("\(ByteFormatter.string(fromByteCount: categoryCoordinator.totalSpaceFreed)) freed this session")
            }

            Divider()

            Button("Open Roomy") {
                openMainWindow()
            }

            emptyTrashButton

            Divider()

            Button("Quit Roomy") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    @ViewBuilder
    private var emptyTrashButton: some View {
        if let trash = categoryCoordinator.results[.trash], !trash.items.isEmpty {
            Button("Empty Trash (\(ByteFormatter.string(fromByteCount: trash.totalSize)))") {
                Task {
                    await categoryCoordinator.emptyTrash()
                }
            }
        } else {
            Button("Empty Trash") {}
                .disabled(true)
        }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Roomy" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}
