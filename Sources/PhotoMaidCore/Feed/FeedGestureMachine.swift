import Foundation

/// Tatsächliche Fingerbewegung (Bildschirmkoordinaten: y wächst nach unten).
public enum SwipeDirection: String, Hashable, Codable, Sendable, CaseIterable {
    case up, down, left, right
    /// Schräg nach rechts oben (ca. 25°–50° über der Waagrechten).
    case rightUp
}

/// Bedeutung einer Fingerbewegung im Entscheidungs-Feed. FEST verdrahtet.
public enum FeedIntent: Hashable, Sendable {
    /// hoch: Behalten, danach nächstes Medium.
    case keep
    /// links: In den PhotoMaid-Papierkorb (nichts wird gelöscht), danach nächstes Medium.
    case markForCleanup
    /// rechts (gerade oder schräg nach unten): Später mit Standardtermin, danach nächstes Medium.
    case later
    /// schräg nach rechts oben: Später, Termin selbst wählen (Drehrad), danach nächstes Medium.
    case laterCustom
    /// runter: vorheriges Medium. Keine Entscheidung.
    case previous

    public init(_ direction: SwipeDirection) {
        switch direction {
        case .up: self = .keep
        case .left: self = .markForCleanup
        case .right: self = .later
        case .rightUp: self = .laterCustom
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

public struct GestureConfig: Hashable, Sendable {
    /// Unterhalb dieser Strecke (pt) keine Richtung.
    public var deadZone: Double = 14
    /// Die dominante Achse muss mindestens um diesen Faktor größer sein als die andere,
    /// damit eine Richtung gebunden wird (diagonale Bewegungen lösen nichts aus).
    public var lockRatio: Double = 1.6
    /// Eine gebundene Richtung löst sich erst, wenn die Strecke entlang der Achse
    /// wieder unter diesen Wert fällt oder das Vorzeichen wechselt (Hysterese).
    public var unlockDistance: Double = 6
    /// Mindeststrecke für einen Commit ohne Schwung.
    public var commitDistance: Double = 110
    /// Schwung (pt/s) entlang der Richtung, der zusammen mit `flickMinDistance` genügt.
    public var flickVelocity: Double = 650
    public var flickMinDistance: Double = 36
    /// Rechts schräg nach oben ab diesem Verhältnis |dy|/|dx| (≈ 25°) = Termin selbst wählen.
    public var rightUpMinRatio: Double = 0.47
    /// … bis zu diesem Verhältnis (≈ 50°). Darüber bis zur Senkrechten: Totzone, dann „hoch“.
    public var rightUpMaxRatio: Double = 1.2
    /// Rechts schräg nach unten bis zu diesem Verhältnis (45°) zählt noch als „rechts“.
    public var rightDownMaxRatio: Double = 1.0
    public init() {}
}

/// Zentrale Gesten-State-Machine des Feeds.
///
/// idle → dragging → directionLocked → commitRequested → (persisted) → idle (nächstes Item)
///
/// Eine abgebrochene Geste führt zurück nach `idle`, ohne Entscheidung.
/// Diese Struktur kennt kein „aktuelles Item“: Der Commit wird von `FeedSession` mit
/// stabiler Item-ID, Revision und Command-ID versehen.
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
    /// Während Zoom, Timeline-Bedienung, aktiver Controls oder VoiceOver-Scrollen: keine Entscheidungsgesten.
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
            case .rightUp: return t   // folgt diagonal: sichtbarer Unterschied zu „rechts“
            }
        }
    }

    public var lockedDirection: SwipeDirection? {
        switch phase {
        case .directionLocked(let d, _), .commitRequested(let d): d
        default: nil
        }
    }

    public mutating func update(translation t: Vector2) {
        guard !isSuspended else { return }
        switch phase {
        case .commitRequested:
            return
        case .idle, .dragging:
            if let d = lockCandidate(t) { phase = .directionLocked(d, t) } else { phase = .dragging(t) }
        case .directionLocked(let d, _) where d == .right || d == .rightUp:
            // Rechts / rechts-oben: der aktuelle Winkel entscheidet; Totzonen lösen die Bindung.
            if t.dx < config.unlockDistance { phase = .dragging(t) }
            else if let nd = lockCandidate(t) { phase = .directionLocked(nd, t) }
            else { phase = .dragging(t) }
        case .directionLocked(let d, _):
            if along(d, t) < config.unlockDistance {
                // Hysterese: erst deutlich zurück, dann ggf. neue Richtung.
                phase = .dragging(t)
                if let nd = lockCandidate(t) { phase = .directionLocked(nd, t) }
            } else {
                phase = .directionLocked(d, t)
            }
        }
    }

    /// Finger losgelassen.
    public mutating func end(translation t: Vector2, velocity v: Vector2) -> Resolution {
        guard !isSuspended else { phase = .idle; return .ignored }
        switch phase {
        case .commitRequested:
            return .ignored
        case .idle:
            return .ignored
        case .dragging:
            phase = .idle
            return .cancelled
        case .directionLocked(let d, _):
            let distance = along(d, t)
            let speed = along(d, v)
            let offAxis = across(d, t)
            let clearlyDirected = (d == .right || d == .rightUp)
                ? lockCandidate(t) == d
                : offAxis * config.lockRatio <= max(distance, 0)
            if clearlyDirected && (distance >= config.commitDistance
                || (speed >= config.flickVelocity && distance >= config.flickMinDistance)) {
                phase = .commitRequested(d)
                return .commit(d)
            }
            phase = .idle
            return .cancelled
        }
    }

    /// Systemabbruch (z. B. Unterbrechung, Hintergrund, Rotation). Keine Entscheidung.
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
        if t.dy < 0 {
            if ratio < config.rightUpMinRatio { return .right }
            return ratio <= config.rightUpMaxRatio ? .rightUp : nil
        }
        return ratio <= config.rightDownMaxRatio ? .right : nil
    }

    /// Strecke in Richtung `d` (negativ bei Gegenrichtung).
    private func along(_ d: SwipeDirection, _ t: Vector2) -> Double {
        switch d {
        case .up: -t.dy
        case .down: t.dy
        case .left: -t.dx
        case .right, .rightUp: t.dx
        }
    }

    private func across(_ d: SwipeDirection, _ t: Vector2) -> Double {
        switch d {
        case .up, .down: abs(t.dx)
        case .left, .right, .rightUp: abs(t.dy)
        }
    }
}
