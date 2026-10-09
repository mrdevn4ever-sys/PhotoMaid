import Foundation

/// Tatsächliche Fingerbewegung (Bildschirmkoordinaten: y wächst nach unten).
public enum SwipeDirection: String, Hashable, Codable, Sendable, CaseIterable {
    case up, down, left, right
}

/// Bedeutung einer Fingerbewegung im Entscheidungs-Feed. FEST verdrahtet.
public enum FeedIntent: Hashable, Sendable {
    /// hoch: Behalten, danach nächstes Medium.
    case keep
    /// links: In den PhotoMaid-Papierkorb (nichts wird gelöscht), danach nächstes Medium.
    case markForCleanup
    /// rechts (gerade oder schräg nach oben/unten bis 45°): Später mit Standardtermin, danach nächstes Medium.
    case later
    /// Später mit selbst gewähltem Termin. Keine Geste (Entscheidung E2: die Diagonale entfällt, der Termin wird über
    /// „Ändern“ in der Pille gewählt). Nur als VoiceOver-/Schalter-Aktion; öffnet erst die Auswahl,
    /// erst Bestätigen = Später + nächstes Medium.
    case laterCustom
    /// runter: vorheriges Medium. Keine Entscheidung.
    case previous

    public init(_ direction: SwipeDirection) {
        switch direction {
        case .up: self = .keep
        case .left: self = .markForCleanup
        case .right: self = .later
        case .down: self = .previous
        }
    }

    public var isDecision: Bool { self != .previous }
}

public struct Vector2: Hashable, Sendable {
    public var dx: Double
    public var dy: Double
    public init(_ dx: Double, _ dy: Double) { self.dx = dx; self.dy = dy }
    public static let zero = Vector2(0, 0)
}

/// Schwellen in pt (Android: dp – beide dichteunabhängig). Wie Android nach dem Gerätebefund 2026-10-04
/// („zu schwerfällig“): 72 pt, Schwung ab 380 pt/s und 20 pt, Achse bis ≈ 38° (lockRatio 1,3).
/// Zwischen „rechts“ (≤ 45°) und „hoch“/„runter“ bleibt eine Totzone.
public struct GestureConfig: Hashable, Sendable {
    /// Unterhalb dieser Strecke keine Richtung.
    public var deadZone: Double = 14
    /// Dominante Achse muss um diesen Faktor größer sein (Diagonalen lösen nichts aus).
    public var lockRatio: Double = 1.3
    /// Hysterese: Bindung löst sich erst unterhalb dieser Strecke entlang der Achse.
    public var unlockDistance: Double = 6
    /// Mindeststrecke für einen Commit ohne Schwung.
    public var commitDistance: Double = 72
    /// Schwung (pt/s) entlang der Richtung, der zusammen mit `flickMinDistance` genügt.
    public var flickVelocity: Double = 380
    public var flickMinDistance: Double = 20
    /// Rechts schräg nach oben bis 45° (|dy|/|dx| ≤ 1) zählt als „rechts“. Darüber bis „hoch“: Totzone.
    public var rightUpMaxRatio: Double = 1.0
    /// Rechts schräg nach unten bis 45° zählt als „rechts“. Darüber bis „runter“: Totzone.
    public var rightDownMaxRatio: Double = 1.0
    public init() {}
}

/// Zentrale Gesten-State-Machine des Feeds (einzige im Projekt).
///
/// idle → dragging → directionLocked → commitRequested → (persistiert) → idle (nächstes Item)
///
/// Eine abgebrochene Geste führt zurück nach `idle`, ohne Entscheidung. Diese Struktur kennt kein
/// „aktuelles Item“: Der Commit wird von `FeedSession` mit Item-ID, Revision und Command-ID versehen.
public struct FeedGestureMachine: Hashable, Sendable {
    public enum Phase: Hashable, Sendable {
        case idle
        case dragging(Vector2)
        case directionLocked(SwipeDirection, Vector2)
        /// Wartet auf Persistenz bzw. Navigation. Weitere Gesten werden ignoriert.
        case commitRequested(SwipeDirection)
    }

    public enum Resolution: Hashable, Sendable {
        case commit(SwipeDirection)
        case cancelled
        case ignored
    }

    public private(set) var phase: Phase = .idle
    public var config: GestureConfig
    /// Während Zoom, Control-Bedienung oder VoiceOver: keine Entscheidungsgesten.
    public var isSuspended = false

    public init(config: GestureConfig = GestureConfig()) { self.config = config }

    /// Versatz, dem das Medium folgt. Nach Richtungsbindung nur noch entlang der Achse.
    public var displayOffset: Vector2 {
        switch phase {
        case .idle, .commitRequested: return .zero
        case .dragging(let t): return t
        case .directionLocked(let d, let t):
            switch d {
            case .up, .down: return Vector2(0, t.dy)
            case .left, .right: return Vector2(t.dx, 0)
            }
        }
    }

    public var lockedDirection: SwipeDirection? {
        switch phase {
        case .directionLocked(let d, _), .commitRequested(let d): d
        default: nil
        }
    }

    /// Würde Loslassen an dieser Stelle (ohne Schwung) eine Entscheidung auslösen? Nur Anzeige/Haptik –
    /// dieselbe Bedingung wie in `end`, die Schwellen bleiben unverändert. „Runter“ ist keine Entscheidung.
    public var readyToCommit: Bool {
        guard case .directionLocked(let d, let t) = phase, d != .down else { return false }
        let distance = along(d, t)
        let directed = d == .right ? lockCandidate(t) == d : across(d, t) * config.lockRatio <= max(distance, 0)
        return directed && distance >= config.commitDistance
    }

    public mutating func update(translation t: Vector2) {
        guard !isSuspended else { return }
        switch phase {
        case .commitRequested:
            return
        case .idle, .dragging:
            if let d = lockCandidate(t) { phase = .directionLocked(d, t) } else { phase = .dragging(t) }
        case .directionLocked(let d, _) where d == .right:
            // Rechts: der aktuelle Winkel entscheidet; Totzonen lösen die Bindung.
            if t.dx < config.unlockDistance { phase = .dragging(t) }
            else if let nd = lockCandidate(t) { phase = .directionLocked(nd, t) }
            else { phase = .dragging(t) }
        case .directionLocked(let d, _):
            if along(d, t) < config.unlockDistance {
                // Hysterese: erst deutlich zurück, dann ggf. neue Richtung.
                if let nd = lockCandidate(t) { phase = .directionLocked(nd, t) } else { phase = .dragging(t) }
            } else {
                phase = .directionLocked(d, t)
            }
        }
    }

    /// Finger losgelassen.
    public mutating func end(translation t: Vector2, velocity v: Vector2) -> Resolution {
        guard !isSuspended else { phase = .idle; return .ignored }
        switch phase {
        case .commitRequested, .idle:
            return .ignored
        case .dragging:
            phase = .idle
            return .cancelled
        case .directionLocked(let d, _):
            let distance = along(d, t)
            let speed = along(d, v)
            let offAxis = across(d, t)
            let clearlyDirected = d == .right ? lockCandidate(t) == d : offAxis * config.lockRatio <= max(distance, 0)
            if clearlyDirected && (distance >= config.commitDistance
                || (speed >= config.flickVelocity && distance >= config.flickMinDistance)) {
                phase = .commitRequested(d)
                return .commit(d)
            }
            phase = .idle
            return .cancelled
        }
    }

    /// Systemabbruch (Unterbrechung, Hintergrund, Rotation). Keine Entscheidung.
    public mutating func cancel() { phase = .idle }

    /// Nach Persistenz bzw. abgeschlossener Navigation (oder Rücksetzen bei Fehler).
    public mutating func finishCommit() { phase = .idle }

    // MARK: Geometrie

    private func lockCandidate(_ t: Vector2) -> SwipeDirection? {
        let ax = abs(t.dx), ay = abs(t.dy)
        guard max(ax, ay) >= config.deadZone else { return nil }
        if ay >= ax * config.lockRatio { return t.dy < 0 ? .up : .down }
        if t.dx < 0 { return ax >= ay * config.lockRatio ? .left : nil }
        let ratio = ay / ax
        let maxRatio = t.dy < 0 ? config.rightUpMaxRatio : config.rightDownMaxRatio
        return ratio <= maxRatio ? .right : nil
    }

    /// Strecke in Richtung `d` (negativ bei Gegenrichtung).
    private func along(_ d: SwipeDirection, _ t: Vector2) -> Double {
        switch d {
        case .up: -t.dy
        case .down: t.dy
        case .left: -t.dx
        case .right: t.dx
        }
    }

    private func across(_ d: SwipeDirection, _ t: Vector2) -> Double {
        switch d {
        case .up, .down: abs(t.dx)
        case .left, .right: abs(t.dy)
        }
    }
}
