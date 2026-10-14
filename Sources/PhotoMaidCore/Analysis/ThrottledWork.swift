import Foundation

public enum ThrottledWorkError: Error, Equatable {
    /// Gerät kritisch heiß: angehalten (Fortschritt bleibt beim Aufrufer gespeichert).
    case critical
}

/// Arbeitet eine Liste in fester Reihenfolge ab, mit höchstens so vielen gleichzeitigen Aufträgen, wie die Wärme
/// erlaubt (`WorkThrottle`). Bei „warm“ werden keine neuen Aufträge gestartet; ist nichts mehr in Arbeit, wird
/// gewartet, bis es kühler ist, und dann von selbst weitergemacht. Nur bei „kritisch“ wird abgebrochen.
/// Ergebnisse werden nacheinander (nie gleichzeitig) an `result` gegeben.
public enum ThrottledWork {
    public static func run<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        maxParallel: Int,
        thermal: @escaping @Sendable () -> WorkThermalLevel,
        coolingPoll: Duration = .seconds(3),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        beforeStart: () throws -> Void = {},
        waiting: () async -> Void = {},
        work: @escaping @Sendable (Input) async throws -> Output,
        result: (Int, Output) async throws -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: (Int, Output).self) { group in
            var cursor = 0
            var inFlight = 0
            while true {
                fill: while cursor < inputs.count {
                    try Task.checkCancellation()
                    switch WorkThrottle.decide(thermal(), maxParallel: maxParallel) {
                    case .stop:
                        throw ThrottledWorkError.critical
                    case .waitForCooling:
                        if inFlight > 0 { break fill }
                        await waiting()
                        try await sleep(coolingPoll)
                    case .run(let parallel, let pause):
                        if inFlight >= parallel { break fill }
                        try beforeStart()
                        if pause > 0 { try await sleep(.milliseconds(pause)) }
                        let index = cursor
                        let input = inputs[index]
                        cursor += 1
                        inFlight += 1
                        group.addTask { (index, try await work(input)) }
                    }
                }
                guard inFlight > 0, let (index, output) = try await group.next() else { break }
                inFlight -= 1
                try await result(index, output)
            }
        }
    }
}
