import Foundation

/// Identifies both an adjustment and the editing context that created a control/gesture.
public struct RetouchTarget: Hashable, Sendable {
    public let id: UUID
    public let revision: UUID

    public init(id: UUID, revision: UUID) {
        self.id = id
        self.revision = revision
    }
}

/// Value-only access policy shared by bindings, gestures and destructive actions.
/// Callers serialize mutations on the editor's MainActor; no index survives an access.
public struct RetouchSelection: Sendable {
    public private(set) var selectedID: UUID?
    public private(set) var revision = UUID()

    public init() {}

    public mutating func invalidate() { revision = UUID() }

    public mutating func select(_ id: UUID?) {
        guard selectedID != id else { return }
        invalidate()
        selectedID = id
    }

    public mutating func reconcile(_ locals: [LocalAdjustment]) {
        guard let id = selectedID else { return }
        if uniqueIndex(id, in: locals) == nil { select(nil) }
    }

    public func target(in locals: [LocalAdjustment]) -> RetouchTarget? {
        guard let id = selectedID, uniqueIndex(id, in: locals) != nil else { return nil }
        return RetouchTarget(id: id, revision: revision)
    }

    public func local(_ target: RetouchTarget, in locals: [LocalAdjustment]) -> LocalAdjustment? {
        guard let i = index(target, in: locals) else { return nil }
        return locals[i]
    }

    /// Missing, deselected, duplicated or stale targets are a no-op, never a new adjustment.
    @discardableResult
    public func update(_ target: RetouchTarget, in locals: inout [LocalAdjustment],
                       _ change: (inout LocalAdjustment) -> Void) -> Bool {
        guard let i = index(target, in: locals) else { return false }
        var local = locals[i]
        change(&local)
        guard local.id == target.id, local != locals[i] else { return false }
        locals[i] = local
        return true
    }

    public func adjustment(_ target: RetouchTarget, in locals: [LocalAdjustment],
                           keyPath: KeyPath<Adjustments, Float>) -> Float {
        guard let value = local(target, in: locals)?.adjust[keyPath: keyPath], value.isFinite else { return 0 }
        return min(100, max(-100, value))
    }

    @discardableResult
    public func setAdjustment(_ value: Float, target: RetouchTarget, in locals: inout [LocalAdjustment],
                              keyPath: WritableKeyPath<Adjustments, Float>) -> Bool {
        guard value.isFinite else { return false }
        return update(target, in: &locals) { $0.adjust[keyPath: keyPath] = min(100, max(-100, value)) }
    }

    public func radialSize(_ target: RetouchTarget, in locals: [LocalAdjustment]) -> Float {
        guard let local = local(target, in: locals), case .radial(_, let rx, _, _, _) = local.mask,
              rx.isFinite else { return 4 }
        return min(100, max(4, rx * 200))
    }

    @discardableResult
    public func setRadialSize(_ value: Float, target: RetouchTarget, in locals: inout [LocalAdjustment]) -> Bool {
        // Validate before update: NaN is not equal to itself, so an unchanged malformed
        // mask must not be mistaken for a successful edit by the equality check.
        guard value.isFinite, let current = local(target, in: locals),
              case .radial(let c, let rx, let ry, let feather, let invert) = current.mask,
              rx.isFinite, ry.isFinite, c.x.isFinite, c.y.isFinite, feather.isFinite,
              rx > 0, ry > 0 else { return false }
        let newRX = min(100, max(4, value)) / 200
        let newRY = newRX * (ry / rx)
        guard newRY.isFinite, newRY > 0 else { return false }
        return update(target, in: &locals) {
            $0.mask = .radial(center: c, rx: newRX, ry: newRY, feather: feather, invert: invert)
        }
    }

    private func index(_ target: RetouchTarget, in locals: [LocalAdjustment]) -> Int? {
        guard target.revision == revision, target.id == selectedID else { return nil }
        return uniqueIndex(target.id, in: locals)
    }

    private func uniqueIndex(_ id: UUID, in locals: [LocalAdjustment]) -> Int? {
        var match: Int?
        for i in locals.indices where locals[i].id == id {
            guard match == nil else { return nil }
            match = i
        }
        return match
    }
}
