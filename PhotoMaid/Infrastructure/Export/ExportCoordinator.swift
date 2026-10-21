import BackgroundTasks
import Foundation
import Observation
import SwiftUI
import UIKit

/// Lange Exporte (Video, Film, Stapel): immer nur einer zur Zeit, mit Fortschritt und Abbrechen. Wechselt der Nutzer
/// die App, läuft der Export als „fortgesetzte Aufgabe“ weiter (`BGContinuedProcessingTask`, iOS zeigt den Fortschritt);
/// lehnt iOS das ab, bleibt die übliche kurze Hintergrundzeit. Endet die Zeit, wird sauber abgebrochen – es bleibt keine
/// halbe Datei, nichts wird gespeichert (ehrliche Meldung). Der Bildschirm bleibt während des Exports an.
@MainActor
@Observable
final class ExportCoordinator {
    static let shared = ExportCoordinator()

    private(set) var title: String?
    private(set) var progress: Double = 0
    /// Export aus dem Tresor: kein Wachhalten des Bildschirms, keine Fortsetzung im Hintergrund, Abbruch beim Sperren.
    private(set) var vaultOwned = false
    var isBusy: Bool { title != nil }

    private var cancelWork: (() -> Void)?
    private var continued: UncheckedBox<BGContinuedProcessingTask>?
    private var legacyTask: UIBackgroundTaskIdentifier = .invalid
    private var expired = false

    enum Failure: Error { case busy, expired }

    private let screenRequest = UUID()

    func run<T: Sendable>(title: String, vaultOwned: Bool = false,
                          _ work: @escaping @Sendable (_ progress: @escaping @Sendable (Double) -> Void) async throws -> T)
        async throws -> T {
        guard self.title == nil else { throw Failure.busy }
        self.title = title
        self.vaultOwned = vaultOwned
        progress = 0
        expired = false
        if !vaultOwned { ScreenAwake.shared.set(screenRequest, active: true) }
        let coordinator = self
        let task = Task.detached(priority: .userInitiated) { () -> T in
            try await work { p in Task { @MainActor in coordinator.report(p) } }
        }
        cancelWork = { task.cancel() }
        // Tresor: beim Verlassen der App wird gesperrt und abgebrochen – keine Fortsetzung im Hintergrund.
        if !vaultOwned { beginBackground(title: title) }
        defer { finish() }
        do {
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch {
            if expired { throw Failure.expired }
            throw error
        }
    }

    func cancel() { cancelWork?() }

    /// Beim Sperren des Tresors: einen laufenden Tresor-Export sofort abbrechen (kein Klartext über die Sitzung hinaus).
    func cancelVaultWork() { if vaultOwned { cancelWork?() } }

    private func report(_ p: Double) {
        guard title != nil else { return }
        progress = min(1, max(0, p))
        if let t = continued?.value {
            t.progress.totalUnitCount = 1000
            t.progress.completedUnitCount = Int64(progress * 1000)
        }
    }

    private func finish() {
        title = nil
        vaultOwned = false
        cancelWork = nil
        ScreenAwake.shared.set(screenRequest, active: false)
        if let t = continued?.value { t.setTaskCompleted(success: !expired) }
        continued = nil
        if legacyTask != .invalid {
            UIApplication.shared.endBackgroundTask(legacyTask)
            legacyTask = .invalid
        }
    }

    private func onExpired() {
        expired = true
        cancelWork?()
    }

    nonisolated private static func continuedHandler(for coordinator: ExportCoordinator) -> @Sendable (BGTask) -> Void {
        { @Sendable task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let box = UncheckedBox(task)
            task.expirationHandler = { @Sendable in Task { @MainActor in coordinator.onExpired() } }
            Task { @MainActor in
                guard coordinator.title != nil else { box.value.setTaskCompleted(success: false); return }
                coordinator.continued = box
                coordinator.report(coordinator.progress)
            }
        }
    }

    nonisolated private static func legacyHandler(for coordinator: ExportCoordinator) -> @Sendable () -> Void {
        { @Sendable in
            Task { @MainActor in
                coordinator.onExpired()
                if coordinator.legacyTask != .invalid {
                    UIApplication.shared.endBackgroundTask(coordinator.legacyTask)
                    coordinator.legacyTask = .invalid
                }
            }
        }
    }

    private func beginBackground(title: String) {
        let id = (Bundle.main.bundleIdentifier ?? "app.photomaid") + ".export." + UUID().uuidString
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil,
                                                        launchHandler: Self.continuedHandler(for: self))
        if registered {
            let request = BGContinuedProcessingTaskRequest(identifier: id, title: title, subtitle: L("export_bg_subtitle"))
            request.strategy = .fail
            do {
                try BGTaskScheduler.shared.submit(request)
                return
            } catch {
                Diagnostics.log(.video, "continued-task-refused")
            }
        }
        legacyTask = UIApplication.shared.beginBackgroundTask(withName: "PhotoMaid export",
                                                                 expirationHandler: Self.legacyHandler(for: self))
    }
}

/// Fortschrittsanzeige über dem Inhalt während eines Exports (mit Abbrechen).
struct ExportProgressOverlay: View {
    let coordinator: ExportCoordinator

    var body: some View {
        if let title = coordinator.title {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                VStack(spacing: AppSpacing.m) {
                    Text(verbatim: title).font(AppTypography.headline).multilineTextAlignment(.center)
                    ProgressView(value: coordinator.progress).frame(maxWidth: 240)
                    Text(verbatim: CountText.percent(coordinator.progress)).font(AppTypography.footnote.monospacedDigit())
                        .foregroundStyle(AppColors.textSecondary)
                    if !coordinator.vaultOwned {
                        // Im Tresor nicht: Verlassen der App sperrt den Tresor und bricht den Export ab.
                        Text(key: "export_keep_open").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    Button(L("cancel"), role: .cancel) { coordinator.cancel() }.buttonStyle(.pmBordered)
                }
                .padding(AppSpacing.l)
                .frame(maxWidth: 340)
                .glassPanel(radius: 28)
                .padding(AppSpacing.pageMargin)
            }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }
}
