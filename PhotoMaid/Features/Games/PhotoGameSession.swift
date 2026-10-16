import Observation
import PhotoMaidCore

/// The modal owns this context across the hub, both games and their configuration screens.
@MainActor @Observable final class PhotoGameSession {
    private(set) var watchedAnalysis: AnalysisKind?
    func observe(_ kind: AnalysisKind?) {
        if let kind { watchedAnalysis = kind }
    }
}
