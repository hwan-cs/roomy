import Foundation
import Observation

@MainActor
@Observable
final class QuickCleanCoordinator {
    private(set) var appCacheItems: [QuickCleanItem] = []
    private(set) var largeForgottenItems: [QuickCleanItem] = []
    private(set) var isDetecting = false
    private(set) var hasDetected = false

    private var detectTask: Task<Void, Never>?

    func start(scanning root: ScanNode) {
        guard !isDetecting, !hasDetected else {
            return
        }
        isDetecting = true
        detectTask = Task {
            let items = await QuickCleanDetector.detect(in: root)
            appCacheItems = items
                .filter {
                    if case .appCache = $0.reason {
                        return true
                    }
                    return false
                }
                .sorted { $0.size > $1.size }
            largeForgottenItems = items
                .filter {
                    if case .largeAndForgotten = $0.reason {
                        return true
                    }
                    return false
                }
                .sorted { $0.size > $1.size }
            isDetecting = false
            hasDetected = true
        }
    }

    func remove(_ item: QuickCleanItem) {
        appCacheItems.removeAll { $0.id == item.id }
        largeForgottenItems.removeAll { $0.id == item.id }
    }
}
