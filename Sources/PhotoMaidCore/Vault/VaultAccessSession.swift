import Foundation

/// A revocable capability for an unlocked vault. Use monotonic system uptime, not wall-clock time.
/// An asynchronous result may only be published to the session that requested it.
public struct VaultAccessSession: Sendable, Equatable {
    public private(set) var token: UUID?
    public private(set) var lastInteraction: TimeInterval = 0
    public private(set) var timeout: TimeInterval = 120

    public init() {}

    @discardableResult
    public mutating func begin(now: TimeInterval, timeout: TimeInterval) -> UUID {
        let token = UUID()
        self.token = token
        self.lastInteraction = now
        self.timeout = max(1, timeout)
        return token
    }

    public mutating func revoke() {
        token = nil
        lastInteraction = 0
    }

    public func accepts(_ candidate: UUID, now: TimeInterval) -> Bool {
        token == candidate && now.isFinite && now >= lastInteraction && now - lastInteraction < timeout
    }

    @discardableResult
    public mutating func touch(now: TimeInterval) -> Bool {
        guard let token, accepts(token, now: now) else { return false }
        lastInteraction = now
        return true
    }

    public var isOpen: Bool { token != nil }

    public func requiresLock(now: TimeInterval) -> Bool {
        guard let token else { return false }
        return !accepts(token, now: now)
    }
}
