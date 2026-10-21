import PhotoMaidCore
import SwiftUI

/// Same real progress and voluntary results handoff in both games; completion never interrupts a round.
struct PhotoGameAnalysisStatus: View {
    @Environment(\.dismiss) private var dismiss
    let onResults: (SmartReviewKind) -> Void
    @Environment(PhotoGameSession.self) private var session
    private var watched: AnalysisKind? { session.watchedAnalysis }
    @State private var analysis = AnalysisController.shared

    var body: some View {
        Group {
            if let kind = watched {
                if analysis.runKind == kind {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(verbatim: L("memory_analysis_running"))
                                .font(AppTypography.footnote)
                            if let counts = analysis.countsByKind[kind], counts.total > 0 {
                                ProgressView(value: counts.fraction)
                                Text(verbatim: L("ana2_progress", counts.complete, counts.total))
                                    .font(AppTypography.caption).monospacedDigit()
                            }
                        }
                    }
                } else if analysis.stageByKind[kind] == .finished, let route = SmartReviewKind(rawValue: kind.rawValue) {
                    InfoBanner(symbol: "checkmark.circle", title: L("memory_analysis_done"), text: L("memory_analysis_ready"),
                               actionTitle: L("memory_results")) { onResults(route); dismiss() }
                } else {
                    InfoBanner(symbol: "pause.circle", text: stopText(kind))
                }
            }
        }
        .onAppear { session.observe(analysis.runKind) }
        .onChange(of: analysis.runKind) { _, kind in session.observe(kind) }
    }

    private func stopText(_ kind: AnalysisKind) -> String {
        switch analysis.stageByKind[kind] {
        case .waitingWiFi: L("ana2_stage_wifi")
        case .storageError: L("ana2_stage_storage")
        case .privacy: L("ana2_stage_privacy")
        default: L("ana2_stage_paused")
        }
    }
}
