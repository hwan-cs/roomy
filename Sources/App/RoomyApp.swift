import SwiftUI
import AppKit

@main
struct RoomyApp: App {
    @State private var scanCoordinator = ScanCoordinator()
    @State private var categoryCoordinator = CategoryCoordinator()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            if Self.isRunningTests {
                EmptyView()
            } else {
                RootView(
                    scanCoordinator: scanCoordinator,
                    categoryCoordinator: categoryCoordinator
                )
            }
        }
        .defaultSize(width: 980, height: 680)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarExtraContentView(categoryCoordinator: categoryCoordinator)
        } label: {
            MenuBarExtraLabelView(categoryCoordinator: categoryCoordinator)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct RootView: View {
    var scanCoordinator: ScanCoordinator
    var categoryCoordinator: CategoryCoordinator
    @State private var hasFullDiskAccess = FullDiskAccessChecker.currentStatus()
    @State private var bypassedFullDiskAccess = false

    var body: some View {
        if hasFullDiskAccess || bypassedFullDiskAccess {
            MainWindowView(
                scanCoordinator: scanCoordinator,
                categoryCoordinator: categoryCoordinator
            )
        } else {
            FullDiskAccessOnboardingView {
                hasFullDiskAccess = true
            } onContinueWithoutAccess: {
                bypassedFullDiskAccess = true
            }
        }
    }
}
