import Foundation
import Photos

/// PhotoKit may complete synchronously, after cancellation, or before returning its request ID.
/// Finish the continuation exactly once and cancel IDs that arrive after cancellation.
final class PhotoRequest<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let cancelledValue: Value
    private let cancelRequest: @Sendable (PHImageRequestID) -> Void
    private var continuation: CheckedContinuation<Value, Never>?
    private var result: Value?
    private var completed = false
    private var cancelled = false
    private var id: PHImageRequestID?

    init(cancelledValue: Value, cancel: @escaping @Sendable (PHImageRequestID) -> Void) {
        self.cancelledValue = cancelledValue
        cancelRequest = cancel
    }

    func install(_ continuation: CheckedContinuation<Value, Never>) -> Bool {
        let existing = lock.withLock { () -> Value? in
            if completed { return result }
            self.continuation = continuation
            return nil
        }
        if let existing { continuation.resume(returning: existing); return false }
        return true
    }

    func register(_ id: PHImageRequestID) {
        let cancel = lock.withLock {
            if cancelled { return true }
            if !completed { self.id = id }
            return false
        }
        if cancel { cancelRequest(id) }
    }

    func finish(_ value: Value) {
        let continuation = lock.withLock { () -> CheckedContinuation<Value, Never>? in
            guard !completed else { return nil }
            completed = true; result = value
            defer { self.continuation = nil; id = nil }
            return self.continuation
        }
        continuation?.resume(returning: value)
    }

    func cancel() {
        let pending = lock.withLock { () -> (CheckedContinuation<Value, Never>?, PHImageRequestID?) in
            guard !completed else { return (nil, nil) }
            cancelled = true; completed = true; result = cancelledValue
            defer { continuation = nil; id = nil }
            return (continuation, id)
        }
        pending.0?.resume(returning: cancelledValue)
        if let id = pending.1 { cancelRequest(id) }
    }

    nonisolated static func perform(cancelledValue: Value,
                                    cancel: @escaping @Sendable (PHImageRequestID) -> Void,
                                    request: @escaping @Sendable (@escaping @Sendable (Value) -> Void) -> PHImageRequestID) async -> Value {
        let state = PhotoRequest(cancelledValue: cancelledValue, cancel: cancel)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard state.install(continuation) else { return }
                let id = request { state.finish($0) }
                state.register(id)
            }
        } onCancel: { state.cancel() }
    }
}
