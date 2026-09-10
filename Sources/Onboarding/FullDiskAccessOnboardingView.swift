import AppKit
import SwiftUI

struct FullDiskAccessOnboardingView: View {
    var onAccessGranted: () -> Void
    var onContinueWithoutAccess: () -> Void

    @State private var isChecking = false
    @State private var lastCheckFoundAccessDenied = false

    var body: some View {
        VStack(spacing: 20) {
            icon

            VStack(spacing: 8) {
                Text("Roomy needs Full Disk Access")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text("macOS hides some of the biggest space users from apps by default. This permission only lets Roomy look — it never changes or deletes anything on its own.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            reasonsList

            if lastCheckFoundAccessDenied {
                Label("Roomy still doesn't have access. If you just granted it, macOS sometimes needs Roomy to relaunch before it takes effect.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(12)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            actions

            HStack(spacing: 12) {
                Button("Continue Without It", action: onContinueWithoutAccess)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Opens Roomy without Full Disk Access -- some space will stay hidden")

                Text("·")
                    .foregroundStyle(.tertiary)

                Button("Quit Roomy") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(40)
        .frame(maxWidth: 460)
        .frame(minWidth: 560, minHeight: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task {
            for await status in FullDiskAccessChecker.statusUpdates() {
                if status {
                    onAccessGranted()
                }
            }
        }
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 64, height: 64)
                .shadow(color: Color.accentColor.opacity(0.4), radius: 16, y: 8)

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Full Disk Access lock icon")
    }

    private var reasonsList: some View {
        VStack(spacing: 1) {
            reasonRow(
                symbol: "photo.stack",
                title: "Photos, Mail & Messages caches",
                detail: "Thumbnails and attachments kept locked away from other apps"
            )
            reasonRow(
                symbol: "app.badge",
                title: "Leftover data from deleted apps",
                detail: "macOS has no real uninstaller -- support files stay behind"
            )
            reasonRow(
                symbol: "clock.arrow.circlepath",
                title: "Time Machine local snapshots",
                detail: "Backups stored on this Mac that show up nowhere obvious"
            )
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private func reasonRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                FullDiskAccessChecker.openSystemSettings()
            } label: {
                Text("Open System Settings")
                    .frame(minWidth: 160, minHeight: 22)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint("Opens the Full Disk Access pane in System Settings")

            Button {
                recheck()
            } label: {
                if isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: 160, minHeight: 22)
                } else {
                    Text("I've Granted Access")
                        .frame(minWidth: 160, minHeight: 22)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isChecking)
            .accessibilityLabel("I've granted access")
            .accessibilityHint("Rechecks whether Roomy now has Full Disk Access")
        }
    }

    private func recheck() {
        isChecking = true
        Task.detached(priority: .userInitiated) {
            let granted = FullDiskAccessChecker.currentStatus()
            await MainActor.run {
                isChecking = false
                lastCheckFoundAccessDenied = !granted
                if granted {
                    onAccessGranted()
                }
            }
        }
    }
}

#if DEBUG
#Preview("Default") {
    FullDiskAccessOnboardingView(onAccessGranted: {}, onContinueWithoutAccess: {})
}

#Preview("Dark") {
    FullDiskAccessOnboardingView(onAccessGranted: {}, onContinueWithoutAccess: {})
        .preferredColorScheme(.dark)
}

#Preview("XXL Text") {
    FullDiskAccessOnboardingView(onAccessGranted: {}, onContinueWithoutAccess: {})
        .dynamicTypeSize(.accessibility3)
}
#endif
