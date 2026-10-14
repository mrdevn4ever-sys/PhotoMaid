import AppTrackingTransparency
import Foundation
import GoogleMobileAds
import Observation
import PhotoMaidCore
import UIKit
import UserMessagingPlatform

/// Werbung in der Gratis-Version (E1/E19, Nutzerentscheidung 14.10.2026): Google Mobile Ads (AdMob).
/// - Erst Einwilligung (UMP: DSGVO/Schweiz/UK), dann die iOS-Tracking-Abfrage (ATT), erst danach startet das SDK.
/// - Nie mit Pro. Anfragen enthalten nie Medien, Dateinamen, Pfade, Hashes oder Kennungen aus der Mediathek –
///   nur die leere Standard-Anfrage (`Request()`).
/// - Freigeschaltet wird nur nach dem Belohnungs-Callback des SDK (`RewardOutcome.earned`).
/// - Kann gerade keine Werbung geladen werden, passiert nichts (kein Zwang, kein toter Knopf).
@MainActor @Observable
final class AdsService: NSObject {
    static let shared = AdsService()

    /// Einwilligung geklärt und SDK gestartet: Werbung darf angefragt werden.
    private(set) var ready = false
    /// „Werbe-Einwilligung ändern“ in den Einstellungen zeigen (von Google für EWR/UK/Schweiz verlangt).
    private(set) var privacyOptionsRequired = false
    /// Gerade läuft eine Vollbild-Werbung (der Tresor zählt das als Bedienung).
    private(set) var presenting = false
    /// Nummer dieses Kaltstarts seit der Installation (1 = erster Start).
    let launchNumber: Int
    @ObservationIgnored private let launchedAt = ProcessInfo.processInfo.systemUptime

    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var rewarded: RewardedAd?
    @ObservationIgnored private var nativeCache: NativeAd?
    @ObservationIgnored private var nativeFetcher: NativeAdFetcher?
    @ObservationIgnored private var nativeWaiters: [(NativeAd?) -> Void] = []
    @ObservationIgnored private var nativeLoading = false
    @ObservationIgnored private var lastNativeAttempt: TimeInterval = -.infinity
    @ObservationIgnored private var dismissal: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var appOpenHandled = false

    private override init() {
        let count = UserDefaults.standard.integer(forKey: "ads.launchCount") + 1
        UserDefaults.standard.set(count, forKey: "ads.launchCount")
        launchNumber = count
        super.init()
    }

    /// Werbung kommt in diesem Build und für diesen Nutzer überhaupt in Frage (nicht Pro, Kaufstatus geklärt, keine
    /// QA-Testdaten – Bildschirmfotos und UI-Tests ohne Einwilligungsdialoge).
    func allowed(_ app: AppModel) -> Bool {
        configured(app) && app.capabilities.adsAllowed
    }

    /// Werbung ist in diesem Build eingerichtet (und keine QA-Testdaten). Sonst wird nichts hinter Werbung gesperrt.
    func configured(_ app: AppModel) -> Bool { AppConfig.adMob != nil && !app.isQAFixtureMode }

    /// Kann gerade Werbung angefragt werden (nach `prepare`)? Für Entscheidungen der Oberfläche (z. B. Tresor-Ordner).
    var canRequestAds: Bool { ready && ConsentInformation.shared.canRequestAds }

    // MARK: Einwilligung, Tracking-Abfrage, Start

    /// Nach dem Einführungsbildschirm und bei jedem Start: Einwilligung klären, ggf. Tracking-Abfrage, SDK starten.
    func prepare(app: AppModel) async {
        guard allowed(app) else { return }
        if ready { return }
        if let preparation { await preparation.value; return }
        let task = Task { await self.runPreparation() }
        preparation = task
        await task.value
        // Fehlgeschlagen (z. B. offline): beim nächsten Mal erneut versuchen.
        if !ready { preparation = nil }
    }

    private func runPreparation() async {
        let consent = ConsentInformation.shared
        do {
            try await consent.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
            Diagnostics.error(.ads, "consent-failed", error)
        }
        privacyOptionsRequired = consent.privacyOptionsRequirementStatus == .required
        // Tracking-Abfrage (Nutzerentscheidung 14.10.2026): einmal, nur in der aktiven App, erst nach der Einwilligung.
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined,
           UIApplication.shared.applicationState == .active {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        guard consent.canRequestAds else {
            Diagnostics.log(.ads, "no-consent")
            return
        }
        MobileAds.shared.start(completionHandler: nil)
        ready = true
        Diagnostics.log(.ads, "started")
    }

    /// Einstellungen › Werbe-Einwilligung ändern.
    func presentPrivacyOptions() async {
        do { try await ConsentForm.presentPrivacyOptionsForm(from: nil) } catch {
            Diagnostics.error(.ads, "privacy-options-failed", error)
        }
        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    // MARK: Werbung beim Start

    /// Kaltstart: ab dem 4. Start eine App-Start-Werbung (E19). Lädt sie nicht innerhalb von 4 s, entfällt sie – der
    /// Nutzer ist dann schon in der App. Nie über dem Tresor, dem Feed oder einem Vollbild.
    func showAppOpenIfDue(app: AppModel) async {
        guard !appOpenHandled else { return }
        appOpenHandled = true
        guard let units = AppConfig.adMob,
              AppOpenAdPolicy.shouldShow(launchNumber: launchNumber, adsAllowed: app.capabilities.adsAllowed) else { return }
        // Nur direkt nach dem Start (nicht, wenn der Kaufstatus erst viel später geklärt wird).
        let started = ProcessInfo.processInfo.systemUptime
        guard started - launchedAt < 15 else { return }
        await prepare(app: app)
        guard canRequestAds else { return }
        let ad: AppOpenAd
        do { ad = try await AppOpenAd.load(with: units.appOpen, request: Request()) } catch {
            Diagnostics.error(.ads, "app-open-load-failed", error)
            return
        }
        guard ProcessInfo.processInfo.systemUptime - started < 4, UIApplication.shared.applicationState == .active,
              app.capabilities.adsAllowed, app.feed == nil, app.fullScreen == nil, !VaultStore.shared.isPresented else {
            return
        }
        await presentFullScreen(ad) { ad.present(from: nil) }
    }

    // MARK: Belohnungsvideo (+100 heute, Tresor-Ordner)

    enum RewardOutcome: Equatable, Sendable {
        /// Belohnung vom SDK bestätigt (eigene Kennung für die idempotente Buchung).
        case earned(rewardID: String)
        /// Vorzeitig geschlossen: nichts freigeschaltet.
        case dismissed
        /// Gerade keine Werbung (offline, keine Anzeige, keine Einwilligung): nichts freigeschaltet.
        case unavailable
    }

    /// Lädt ein Belohnungsvideo vorab (z. B. sobald das Limit-Blatt oder der Ordner-Dialog erscheint).
    func preloadRewarded(app: AppModel) {
        guard rewarded == nil, let units = AppConfig.adMob, allowed(app) else { return }
        Task {
            await prepare(app: app)
            guard canRequestAds, rewarded == nil else { return }
            rewarded = try? await RewardedAd.load(with: units.rewarded, request: Request())
        }
    }

    func showRewarded(app: AppModel) async -> RewardOutcome {
        guard let units = AppConfig.adMob, allowed(app) else { return .unavailable }
        await prepare(app: app)
        guard canRequestAds else { return .unavailable }
        let ad: RewardedAd
        if let cached = rewarded {
            ad = cached
            rewarded = nil
        } else {
            do { ad = try await RewardedAd.load(with: units.rewarded, request: Request()) } catch {
                Diagnostics.error(.ads, "rewarded-load-failed", error)
                return .unavailable
            }
        }
        let flag = RewardFlag()
        await presentFullScreen(ad) { ad.present(from: nil) { flag.set() } }
        return flag.value ? .earned(rewardID: UUID().uuidString) : .dismissed
    }

    // MARK: Werbekarte im Feed

    /// Eine Anzeige für die Werbekarte vorab laden, damit sie ohne Wartezeit erscheint.
    func preloadNative(app: AppModel) {
        guard nativeCache == nil else { return }
        startNativeFetch(app: app)
    }

    /// Anzeige für die Werbekarte: die vorab geladene sofort, sonst eine neue (nach einem Fehlschlag frühestens nach
    /// 30 s wieder). `nil` = keine Anzeige, dann gibt es eben keine Karte.
    func nativeAd(app: AppModel, completion: @escaping (NativeAd?) -> Void) {
        if let cached = nativeCache {
            nativeCache = nil
            completion(cached)
            return
        }
        guard allowed(app) else { completion(nil); return }
        nativeWaiters.append(completion)
        startNativeFetch(app: app)
    }

    private func startNativeFetch(app: AppModel) {
        guard !nativeLoading else { return } // Wartende werden bedient, sobald die laufende Anfrage endet.
        let now = ProcessInfo.processInfo.systemUptime
        guard let units = AppConfig.adMob, allowed(app), now - lastNativeAttempt >= 30 else { flushNative(); return }
        lastNativeAttempt = now
        nativeLoading = true
        Task {
            await prepare(app: app)
            guard canRequestAds else {
                nativeLoading = false
                flushNative()
                return
            }
            let fetcher = NativeAdFetcher()
            nativeFetcher = fetcher
            fetcher.fetch(unit: units.native) { ad in
                self.nativeFetcher = nil
                self.nativeLoading = false
                if let ad {
                    if self.nativeCache == nil { self.nativeCache = ad }
                    self.lastNativeAttempt = -.infinity
                }
                self.flushNative()
            }
        }
    }

    /// Wartende bedienen: die geladene Anzeige an den ersten, alle weiteren bekommen keine.
    private func flushNative() {
        let waiters = nativeWaiters
        nativeWaiters = []
        for waiter in waiters {
            let ad = nativeCache
            nativeCache = nil
            waiter(ad)
        }
    }

    // MARK: Vollbild zeigen und auf das Schließen warten

    private func presentFullScreen(_ ad: some FullScreenPresentingAd, show: () -> Void) async {
        ad.fullScreenContentDelegate = self
        presenting = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dismissal = continuation
            show()
        }
        presenting = false
    }

    private func finishPresentation() {
        dismissal?.resume()
        dismissal = nil
    }
}

extension AdsService: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) { finishPresentation() }

    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        Diagnostics.error(.ads, "present-failed", error)
        finishPresentation()
    }
}

/// Belohnung bestätigt? (Der Callback des SDK kommt vor dem Schließen.)
private final class RewardFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var earned = false
    var value: Bool { lock.withLock { earned } }
    func set() { lock.withLock { earned = true } }
}

/// Lädt genau eine native Anzeige (Werbekarte im Feed).
@MainActor
private final class NativeAdFetcher: NSObject, NativeAdLoaderDelegate {
    private var loader: AdLoader?
    private var completion: ((NativeAd?) -> Void)?

    func fetch(unit: String, completion: @escaping (NativeAd?) -> Void) {
        self.completion = completion
        let placement = NativeAdViewAdOptions()
        placement.preferredAdChoicesPosition = .topRightCorner
        let loader = AdLoader(adUnitID: unit, rootViewController: nil, adTypes: [.native], options: [placement])
        loader.delegate = self
        self.loader = loader
        loader.load(Request())
    }

    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) { finish(nativeAd) }

    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: any Error) {
        Diagnostics.error(.ads, "native-load-failed", error)
        finish(nil)
    }

    private func finish(_ ad: NativeAd?) {
        let done = completion
        completion = nil
        loader = nil
        done?(ad)
    }
}

/// Tresor › Neuer Ordner (E19): mit Pro frei, sonst je Ordner ein Belohnungsvideo. Ein verdientes Video verfällt
/// nicht, wenn der Namensdialog abgebrochen wird (gespeichert wird nur eine Zahl).
@MainActor
enum VaultFolderGate {
    private static let creditsKey = "vault.folderAdCredits"

    static var credits: Int {
        get { UserDefaults.standard.integer(forKey: creditsKey) }
        set { UserDefaults.standard.set(max(0, newValue), forKey: creditsKey) }
    }

    /// Was beim Tippen auf „Neuer Ordner“ passiert.
    static func access(_ app: AppModel) -> VaultFolderAccess {
        let rule = VaultFolderAccess.resolve(app.capabilities, adsConfigured: AdsService.shared.configured(app),
                                             canRequestAds: true)
        return rule == .watchAd && credits > 0 ? .free : rule
    }

    /// Ordner wurde angelegt: ein verdientes Video verbrauchen (nicht bei Pro oder ohne Werbung im Build).
    static func folderCreated(_ app: AppModel) {
        guard VaultFolderAccess.resolve(app.capabilities, adsConfigured: AdsService.shared.configured(app),
                                        canRequestAds: true) != .free else { return }
        credits -= 1
    }

    /// Video zeigen. `true` = verdient (dann darf ein Ordner angelegt werden). Die Tresor-Sitzung läuft dabei weiter.
    static func watchAd(_ app: AppModel) async -> AdsService.RewardOutcome {
        let outcome = await AdsService.shared.showRewarded(app: app)
        VaultStore.shared.touch()
        if case .earned = outcome { credits += 1 }
        return outcome
    }
}
