import Foundation

/// Identity rules shared by every public PhotoMaid surface. A derived output is
/// private if any ancestor is private, including collages with mixed inputs.
public enum VaultVisibilityPolicy {
    public static func closure(roots: Set<String>, parentsByOutput: [String: Set<String>]) -> Set<String> {
        var children: [String: Set<String>] = [:]
        for (output, parents) in parentsByOutput {
            for parent in parents { children[parent, default: []].insert(output) }
        }
        var denied = roots
        var queue = Array(roots)
        var cursor = 0
        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            for child in children[current] ?? [] where denied.insert(child).inserted { queue.append(child) }
        }
        return denied
    }

    public static func allows(_ token: String, ready: Bool, denied: Set<String>) -> Bool {
        ready && !denied.contains(token)
    }
}

public enum VaultSessionError: Error, Equatable, Sendable { case expired }

/// Revoking a session invalidates keys retained by asynchronous work. A new
/// unlock never revalidates an old lease. No actor or UI assumptions are needed.
public final class VaultSessionFence: @unchecked Sendable {
    public struct Lease: Sendable {
        fileprivate let owner: VaultSessionFence
        fileprivate let generation: UUID
        public var isValid: Bool { owner.check(generation) }
        public func requireValid() throws {
            guard isValid else { throw VaultSessionError.expired }
        }
        /// Synchronous file creation/write must use this method: it is atomic
        /// with revoke, so an expired task cannot recreate plaintext after lock.
        public func withValidity<T>(_ body: () throws -> T) throws -> T {
            try owner.withValidity(generation, body)
        }
    }
    private let lock = NSRecursiveLock()
    private var generation = UUID()
    private var active = false
    public init() {}
    @discardableResult public func activate() -> Lease {
        lock.lock(); defer { lock.unlock() }
        generation = UUID(); active = true
        return Lease(owner: self, generation: generation)
    }
    public func lease() throws -> Lease {
        lock.lock(); defer { lock.unlock() }
        guard active else { throw VaultSessionError.expired }
        return Lease(owner: self, generation: generation)
    }
    public func revoke() {
        lock.lock(); defer { lock.unlock() }
        active = false; generation = UUID()
    }
    private func check(_ candidate: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return active && generation == candidate
    }
    private func withValidity<T>(_ candidate: UUID, _ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard active && generation == candidate else { throw VaultSessionError.expired }
        return try body()
    }
}

public enum VaultTransaction {
    /// Memory is published only after the proposed value is durably persisted.
    /// Ciphertext removal may follow success, never a failed index write.
    public static func update<Value>(_ current: inout Value, mutate: (inout Value) throws -> Void,
                                     persist: (Value) throws -> Void) throws {
        var proposed = current
        try mutate(&proposed)
        try persist(proposed)
        current = proposed
    }
}

public enum VaultPathRules {
    public static func isComponent(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") &&
        !name.contains("\\") && !name.contains("\0") && name.utf8.count <= 255
    }
    /// Original filenames are metadata, never trusted paths for decrypted data.
    public static func temporaryName(id: UUID = UUID(), fileExtension: String?) -> String {
        let ext = fileExtension?.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let base = id.uuidString
        return ext.map { !$0.isEmpty && $0.count <= 12 ? base + "." + $0 : base } ?? base
    }
}
