import UIKit

/// Ordinary, silent background time. No continued-processing request or Live Activity.
/// Expiration checkpoints the analysis; it is never presented as a failed system job.
@MainActor final class AnalysisBackgroundTime {
    typealias Begin = @MainActor (@escaping @Sendable () -> Void) -> UIBackgroundTaskIdentifier
    typealias End = @MainActor (UIBackgroundTaskIdentifier) -> Void
    private let beginTask: Begin
    private let endTask: End
    private var identifier = UIBackgroundTaskIdentifier.invalid
    private var generation: UUID?
    var isActive: Bool { identifier != .invalid }

    init(begin: @escaping Begin = { UIApplication.shared.beginBackgroundTask(withName: "PhotoMaid analysis", expirationHandler: $0) },
         end: @escaping End = { UIApplication.shared.endBackgroundTask($0) }) {
        beginTask = begin; endTask = end
    }

    @discardableResult func begin(onExpiration: @escaping @MainActor () -> Void) -> Bool {
        guard !isActive else { return true }
        let token = UUID(); generation = token
        identifier = beginTask { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.end()
                onExpiration()
            }
        }
        if identifier == .invalid { generation = nil }
        return isActive
    }

    func end() {
        generation = nil
        guard identifier != .invalid else { return }
        let ended = identifier; identifier = .invalid
        endTask(ended)
    }

    nonisolated static func isLegacyAnalysisRequest(_ identifier: String, bundleID: String) -> Bool {
        let prefix = bundleID + ".analysis."
        return identifier.hasPrefix(prefix) && UUID(uuidString: String(identifier.dropFirst(prefix.count))) != nil
    }
}
