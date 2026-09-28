import PhotoMaidCore
import SwiftUI

/// Screen 5 – Auswahlkorb. Reale Kandidaten, Vorschau, Abwahl, genaue Beschreibung der Operation.
/// Gemischter Korb wird nach Provider/Operation getrennt bestätigt.
struct CleanupBasketView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<ItemReference> = []
    @State private var assets: [String: MediaAsset] = [:]
    @State private var confirmPhotos = false
    @State private var confirmFiles = false
    @State private var running = false
    @State private var resultMessage: String?
    @State private var showPro = false

    private var photoItems: [ItemRecord] { app.basket.filter { $0.item.provider == .photoLibrary } }
    private var fileItems: [ItemRecord] { app.basket.filter { $0.item.provider != .photoLibrary } }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("\(app.basket.count) Elemente vorgemerkt").font(AppTypography.title)
                    Text("Prüfe die Auswahl, bevor etwas entfernt wird. Abgewählte Elemente bleiben erhalten.")
                        .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                    if let a = app.allowance, let available = a.available {
                        Text("Heute noch \(available) von \(a.limit ?? 0) Bereinigungen frei")
                            .font(AppTypography.caption.weight(.semibold))
                            .foregroundStyle(available == 0 ? AppColors.cleanup : AppColors.textSecondary)
                    }
                }
                .listRowBackground(Color.clear)
            }
            if !photoItems.isEmpty {
                Section {
                    ForEach(photoItems, id: \.item) { r in row(r) }
                } header: {
                    Text("Fotos & Videos")
                } footer: {
                    Text("Wird über die Fotos-App entfernt. iOS fragt dich zur Bestätigung. Die Medien landen in „Zuletzt gelöscht“ und können dort in der Regel noch 30 Tage wiederhergestellt werden. Mit iCloud-Fotos gilt das für alle deine Geräte.")
                }
            }
            if !fileItems.isEmpty {
                Section {
                    ForEach(fileItems, id: \.item) { r in row(r) }
                } header: {
                    Text("Dateien")
                } footer: {
                    Text("Dateien werden endgültig gelöscht. Dafür gibt es keinen Papierkorb und kein Rückgängig.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(Text("Auswahlkorb"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if app.basket.isEmpty {
                EmptyState(symbol: "tray", title: "Auswahlkorb ist leer",
                           message: "Wische im Feed nach links, um Elemente vorzumerken.")
            }
        }
        .safeAreaInset(edge: .bottom) { actions }
        .task(id: app.basket.count) {
            for a in app.photos.assets(ids: photoItems.map(\.item.localIdentifier)) { assets[a.id] = a }
            selection = Set(app.basket.map(\.item))
        }
        .confirmationDialog("Fotos & Videos entfernen?", isPresented: $confirmPhotos, titleVisibility: .visible) {
            Button("\(selectedPhotos.count) über die Fotos-App entfernen", role: .destructive) {
                Task { await run(selectedPhotos, kind: .photoLibraryDelete) }
            }
        } message: {
            Text("Danach bestätigst du im Systemdialog. Die Medien kommen in „Zuletzt gelöscht“.")
        }
        .confirmationDialog("Dateien endgültig löschen?", isPresented: $confirmFiles, titleVisibility: .visible) {
            Button("\(selectedFiles.count) endgültig löschen", role: .destructive) {
                Task { await run(selectedFiles, kind: .fileDeletePermanently) }
            }
        } message: {
            Text("Das kann nicht rückgängig gemacht werden.")
        }
        .alert("Ergebnis", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(resultMessage ?? "") }
        .sheet(isPresented: $showPro) { NavigationStack { ProView() }.environment(app) }
    }

    private var selectedPhotos: [ItemReference] { photoItems.map(\.item).filter { selection.contains($0) } }
    private var selectedFiles: [ItemReference] { fileItems.map(\.item).filter { selection.contains($0) } }

    private func row(_ r: ItemRecord) -> some View {
        HStack(spacing: AppSpacing.s) {
            Button {
                if selection.contains(r.item) { selection.remove(r.item) } else { selection.insert(r.item) }
            } label: {
                Image(systemName: selection.contains(r.item) ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(selection.contains(r.item) ? AppColors.cleanup : AppColors.textSecondary)
                    .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(selection.contains(r.item) ? "Ausgewählt" : "Nicht ausgewählt"))
            if r.item.provider == .photoLibrary {
                ThumbnailView(assetID: r.item.localIdentifier).frame(width: 52, height: 52)
            } else {
                Image(systemName: "doc").font(.title2).frame(width: 52, height: 52)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title(r)).font(AppTypography.subheadline.weight(.semibold)).lineLimit(1)
                if let a = assets[r.item.localIdentifier], let d = a.creationDate {
                    Text(d.formatted(date: .abbreviated, time: .omitted)).font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            Spacer()
        }
        .swipeActions(allowsFullSwipe: false) {
            Button("Behalten") { Task { await app.decide(r.item, .keep) } }.tint(AppColors.keep)
            Button("Abwählen") { Task { await app.decide(r.item, .unmark) } }.tint(.gray)
        }
    }

    private func title(_ r: ItemRecord) -> String {
        if r.item.provider == .photoLibrary {
            switch assets[r.item.localIdentifier]?.kind {
            case .video: return String(localized: "Video")
            case .screenshot: return String(localized: "Screenshot")
            default: return String(localized: "Foto")
            }
        }
        return (r.item.localIdentifier as NSString).lastPathComponent
    }

    private var actions: some View {
        VStack(spacing: AppSpacing.xs) {
            if !selectedPhotos.isEmpty {
                Button { confirmPhotos = true } label: {
                    Text("\(selectedPhotos.count) Fotos/Videos prüfen und entfernen").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).controlSize(.large)
            }
            if !selectedFiles.isEmpty {
                Button(role: .destructive) { confirmFiles = true } label: {
                    Text("\(selectedFiles.count) Dateien endgültig löschen").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass).controlSize(.large)
            }
            if running { ProgressView() }
        }
        .disabled(running)
        .padding(.horizontal, AppSpacing.pageMargin)
        .padding(.bottom, AppSpacing.xs)
    }

    private func run(_ items: [ItemReference], kind: CleanupOperationKind) async {
        running = true
        defer { running = false }
        switch await app.runCleanup(items, kind: kind) {
        case .finished(let intent):
            switch intent.state {
            case .succeeded:
                resultMessage = kind == .photoLibraryDelete
                    ? String(localized: "\(intent.confirmedRemoved.count) Medien wurden in „Zuletzt gelöscht“ verschoben.")
                    : String(localized: "\(intent.confirmedRemoved.count) Dateien wurden endgültig gelöscht.")
            case .partiallySucceeded:
                resultMessage = String(localized: "\(intent.confirmedRemoved.count) von \(intent.items.count) Elementen wurden entfernt. Der Rest bleibt vorgemerkt.")
            case .cancelled:
                resultMessage = String(localized: "Abgebrochen. Es wurde nichts entfernt.")
            default:
                resultMessage = String(localized: "Es wurde nichts entfernt.")
            }
        case .rejected(.allowanceExceeded(let requested, let available)):
            resultMessage = String(localized: "Heute sind noch \(available) Bereinigungen frei, ausgewählt sind \(requested). Wähle bis zu \(available) Elemente aus – oder hol dir PhotoMaid Pro.")
            if available == 0 { showPro = true }
        case .rejected:
            resultMessage = String(localized: "Die Auswahl hat sich geändert. Bitte prüfe sie erneut.")
        case .needsReconciliation:
            resultMessage = String(localized: "Das Ergebnis wird beim nächsten Start abgeglichen. Es wird nichts erneut gelöscht.")
        }
    }
}

/// Kleines Vorschaubild (lokal, ohne Netzwerk).
struct ThumbnailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.displayScale) private var scale
    let assetID: String
    @State private var image: UIImage?
    @State private var notLocal = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(AppColors.backgroundTint)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if notLocal {
                Image(systemName: "icloud").foregroundStyle(AppColors.textSecondary)
            }
        }
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityHidden(true)
        .task(id: assetID) {
            switch await app.preview.image(for: assetID, targetSize: CGSize(width: 60 * scale, height: 60 * scale)) {
            case .image(let img): image = img
            case .notLocallyAvailable: notLocal = true
            case .failed: break
            }
        }
    }
}
