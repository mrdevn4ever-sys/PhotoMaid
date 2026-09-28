import PhotoMaidCore
import SwiftUI

/// Öffentliche Systemwerte zur Gerätekapazität (Anzeige an den Nutzer, Reason 85F4.1).
enum DeviceStorage {
    static func read() -> DeviceCapacity? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = v.volumeTotalCapacity, let avail = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return DeviceCapacity(totalBytes: Int64(total), availableForImportantUsageBytes: avail)
    }
}

/// Screen 1 – Heute: fortsetzbare Review-Session, echte Kennzahlen, Wieder-fällig-Hinweis.
struct TodayView: View {
    @Environment(AppModel.self) private var app
    let openFeed: (FeedRequest) -> Void
    let openSettings: () -> Void
    @State private var counts: [MediaCategory: Int] = [:]
    @State private var pending: Int?
    @State private var device: DeviceCapacity?
    @State private var showPrivacy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                header
                if !app.photos.access.canRead {
                    accessCard
                }
                if let device { storageCard(device) }
                if app.photos.access.canRead { reviewCard }
                if app.dueCount > 0 { dueCard }
                if !app.reconciliationNeeded.isEmpty { reconciliationCard }
                categories
            }
            .padding(.horizontal, AppSpacing.pageMargin)
            .padding(.bottom, AppSpacing.xxl)
        }
        .background(AppBackground())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPrivacy) { PrivacyAccessView().environment(app) }
        .task(id: app.photos.changeToken) { await refresh() }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        device = DeviceStorage.read()
        var c: [MediaCategory: Int] = [:]
        for cat in MediaCategory.allCases { c[cat] = app.photos.count(cat) }
        counts = c
        guard app.photos.access.canRead else { pending = nil; return }
        let refs = (app.photos.assets(.photos) + app.photos.assets(.videos)).map(\.reference)
        let records = await app.ledger.records(for: refs)
        pending = ReviewQueues.normalQueue(candidates: refs, records: records, session: ReviewSessionID(), today: app.today).count
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("PhotoMaid").font(AppTypography.largeTitle).foregroundStyle(AppColors.textPrimary)
                Text("Eine aufgeräumte Galerie für das, was zählt")
                    .font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
            GlassIconButton(symbol: "gearshape", label: "Einstellungen", action: openSettings)
        }
        .padding(.top, AppSpacing.s)
    }

    private var accessCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Label("Zugriff auf Fotos erforderlich", systemImage: "photo.on.rectangle")
                    .font(AppTypography.headline)
                Text(accessText).font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                Button("Mehr erfahren") { showPrivacy = true }.buttonStyle(.glassProminent)
            }
        }
    }

    private var accessText: LocalizedStringKey {
        switch app.photos.access {
        case .denied: "Der Zugriff wurde abgelehnt. Du kannst ihn in den iOS-Einstellungen für PhotoMaid ändern."
        case .restricted: "Der Zugriff ist auf diesem Gerät eingeschränkt (z. B. durch Bildschirmzeit)."
        default: "PhotoMaid braucht Zugriff auf deine Mediathek, um Fotos und Videos zum Sortieren anzuzeigen."
        }
    }

    private func storageCard(_ d: DeviceCapacity) -> some View {
        MetricCard(value: Text(SizeText.bytes(d.usedBytes)),
                   caption: Text("von \(SizeText.bytes(d.totalBytes)) belegt"),
                   progress: d.totalBytes > 0 ? Double(d.usedBytes) / Double(d.totalBytes) : nil,
                   footnote: Text("Systemwert des iPhones, nicht nur Fotos"))
    }

    private var reviewCard: some View {
        Button { openFeed(FeedRequest(source: .category(.photos))) } label: {
            SurfaceCard {
                HStack(spacing: AppSpacing.m) {
                    Image(systemName: "photo.stack").font(.largeTitle).foregroundStyle(AppColors.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        if let pending {
                            Text("\(pending) Elemente").font(AppTypography.title).foregroundStyle(AppColors.textPrimary)
                            Text("warten auf eine Entscheidung").font(AppTypography.subheadline)
                                .foregroundStyle(AppColors.textPrimary)
                        } else {
                            ProgressView()
                        }
                        Text("Mach Platz und behalte, was du liebst.").font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(AppColors.accent).accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Startet die Prüfung deiner Fotos"))
    }

    private var dueCard: some View {
        Button { openFeed(FeedRequest(source: .due)) } label: {
            SurfaceCard {
                Label("\(app.dueCount) zurückgestellte Elemente sind wieder fällig", systemImage: "calendar.badge.clock")
                    .font(AppTypography.headline).foregroundStyle(AppColors.textPrimary)
            }
        }
        .buttonStyle(.plain)
    }

    private var reconciliationCard: some View {
        SurfaceCard {
            Label("Eine frühere Bereinigung konnte nicht eindeutig abgeglichen werden. Es wird nichts erneut gelöscht.",
                  systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                .font(AppTypography.subheadline).foregroundStyle(AppColors.warning)
        }
    }

    private var categories: some View {
        SurfaceCard {
            VStack(spacing: AppSpacing.xs) {
                categoryRow(.photos, "photo", "Fotos")
                Divider()
                categoryRow(.videos, "video.fill", "Videos")
                Divider()
                categoryRow(.screenshots, "camera.viewfinder", "Screenshots")
                Divider()
                NavigationLink { FileBrowserView() } label: {
                    SourceRow(symbol: "arrow.down.circle.fill", tint: .blue,
                              title: app.sources.downloadsSource == nil ? "Dateien" : "Downloads",
                              subtitle: Text(app.sources.sources.isEmpty ? "Ordner auswählen" : "Verbundene Quellen"))
                }.buttonStyle(.plain)
                Divider()
                NavigationLink { DuplicatesView() } label: {
                    SourceRow(symbol: "square.on.square.fill", tint: .indigo, title: "Duplikate",
                              subtitle: Text("Exakt identische Kopien"))
                }.buttonStyle(.plain)
                Divider()
                NavigationLink { LaterView(openFeed: openFeed) } label: {
                    SourceRow(symbol: "bookmark.fill", tint: .teal, title: "Später",
                              value: Text("\(app.laterRecords.count)"), detail: Text("Elemente"))
                }.buttonStyle(.plain)
            }
        }
    }

    private func categoryRow(_ c: MediaCategory, _ symbol: String, _ title: LocalizedStringKey) -> some View {
        Button { openFeed(FeedRequest(source: .category(c))) } label: {
            SourceRow(symbol: symbol, tint: .blue, title: title,
                      value: counts[c].map { Text("\($0)") }, detail: Text("Elemente"))
        }
        .buttonStyle(.plain)
        .disabled(!app.photos.access.canRead)
    }
}
