import AVFoundation
import CryptoKit
import Observation
import PhotoMaidCore
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

struct VaultDocumentScanner: View {
    let completion: (Result<Data, any Error>) -> Void
    @State private var allowed: Bool?
    var body: some View {
        Group {
            if allowed == true { VaultScannerController(completion: completion) }
            else if allowed == false {
                VStack(spacing: 20) {
                    ContentUnavailableView(L("vault2_scan"), systemImage: "camera", description: Text(L("vault2_camera_permission")))
                    Button(L("done")) { completion(.failure(CancellationError())) }
                }
            } else { ProgressView() }
        }
        .task {
            guard VNDocumentCameraViewController.isSupported else { allowed = false; return }
            let lease = try? VaultStore.shared.requireLease()
            let permission = await AVCaptureDevice.requestAccess(for: .video)
            guard let lease, VaultStore.shared.accepts(lease) else { completion(.failure(CancellationError())); return }
            allowed = permission
        }
    }
}

private struct VaultScannerController: UIViewControllerRepresentable {
    let completion: (Result<Data, any Error>) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let view = VNDocumentCameraViewController(); view.delegate = context.coordinator; return view
    }
    func updateUIViewController(_ view: VNDocumentCameraViewController, context: Context) {}
    @MainActor final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        private let completion: (Result<Data, any Error>) -> Void
        private var finished = false
        init(_ completion: @escaping (Result<Data, any Error>) -> Void) { self.completion = completion }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { finish(.failure(CancellationError())) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) { finish(.failure(error)) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard VaultStore.shared.phase == .unlocked, (1...100).contains(scan.pageCount) else { finish(.failure(VaultWorkspaceError.invalidData)); return }
            let bounds = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
            var invalidPage = false
            let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { renderer in
                for index in 0..<scan.pageCount {
                    autoreleasepool {
                        renderer.beginPage()
                        let image = scan.imageOfPage(at: index)
                        guard image.size.width > 0, image.size.height > 0 else { invalidPage = true; return }
                        let available = bounds.insetBy(dx: 18, dy: 18)
                        let scale = min(available.width / image.size.width, available.height / image.size.height)
                        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                        image.draw(in: CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
                    }
                }
            }
            // PDF exists in memory only; caller sends it straight to the encrypted object writer.
            finish((data.isEmpty || invalidPage) ? .failure(VaultWorkspaceError.invalidData) : .success(data))
        }
        private func finish(_ result: Result<Data, any Error>) { guard !finished else { return }; finished = true; completion(result) }
    }
}

/// Audio is encrypted while it is captured, not recorded to an unencrypted .m4a first.
private final class VaultAudioStream: @unchecked Sendable {
    let object: String
    let sampleRate: Double
    private let mutex = NSLock()
    private let writer: VaultFileWriter
    private var ended = false
    private var frames: Int64 = 0
    private var failed = false
    init(object: String, sampleRate: Double, lease: VaultSessionLease) throws {
        self.object = object; self.sampleRate = sampleRate
        let header = try VaultAudioFormat.header(sampleRate: sampleRate)
        writer = try lease.withPermit { try VaultFileWriter(url: VaultStore.objects.appendingPathComponent(object), master: lease.key) }
        writer.receive(header)
    }
    var duration: Double { mutex.withLock { Double(frames) / sampleRate } }
    var hasFailed: Bool { mutex.withLock { failed } }
    func discardIfEmpty() -> Bool {
        mutex.withLock {
            guard frames == 0 else { return false }
            ended = true; writer.abort()
            try? FileManager.default.removeItem(at: VaultStore.objects.appendingPathComponent(object))
            return true
        }
    }
    func receive(_ buffer: AVAudioPCMBuffer) {
        mutex.withLock {
            guard !ended, !failed else { return }
            guard buffer.format.sampleRate == sampleRate, let channels = buffer.floatChannelData, buffer.format.channelCount > 0 else { failed = true; return }
            let count = Int(buffer.frameLength), stride = buffer.stride
            var bytes = Data(capacity: count * 2)
            for i in 0..<count {
                let value = channels[0][i * stride]
                let finite = value.isFinite ? value : 0
                let sample = Int16(max(-32768, min(32767, (finite * 32767).rounded())))
                let bits = UInt16(bitPattern: sample)
                bytes.append(UInt8(bits & 255)); bytes.append(UInt8(bits >> 8))
            }
            writer.receive(bytes); frames += Int64(count)
        }
    }
    func finish() throws -> (size: Int64, sha256: String) {
        try mutex.withLock {
            guard !ended else { throw VaultWorkspaceError.conflict }
            ended = true
            guard !failed, frames > 0 else { writer.abort(); throw VaultWorkspaceError.invalidData }
            return try writer.finish()
        }
    }
    /// The callback is built outside MainActor. Only this thread-safe stream crosses to the audio thread.
    nonisolated static func tap(_ stream: VaultAudioStream) -> AVAudioNodeTapBlock {
        { buffer, _ in stream.receive(buffer) }
    }
}

private struct VaultCaptureCheckpoint: Codable {
    let id: String
    let object: String
    let name: String
    let createdMs: Int64
    let folderID: String?
}

/// A small encrypted checkpoint lets a fully sealed recording survive an index-save failure.
@MainActor enum VaultCaptureRecovery {
    private static var directory: URL { VaultStore.root.appendingPathComponent("c", isDirectory: true) }
    private static func checkpointURL(_ id: String) -> URL { directory.appendingPathComponent(id) }
    fileprivate static func begin(_ value: VaultCaptureCheckpoint, lease: VaultSessionLease) throws {
        try lease.withPermit {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            let bytes = try VaultCrypto.seal(JSONEncoder().encode(value), key: VaultCrypto.subkey(lease.key, salt: [], info: "pm-vault-capture"))
            try bytes.write(to: checkpointURL(value.id), options: [.atomic, .completeFileProtection])
        }
    }
    fileprivate static func discardEmptyCheckpoint(_ value: VaultCaptureCheckpoint) {
        try? FileManager.default.removeItem(at: checkpointURL(value.id))
    }
    fileprivate static func complete(_ value: VaultCaptureCheckpoint, lease: VaultSessionLease, store: VaultStore) throws {
        let digest = try VaultFileReader.digest(VaultStore.objects.appendingPathComponent(value.object), master: lease.key)
        let file = VaultDocument(id: value.id, name: value.name, objectName: value.object,
            typeIdentifier: UTType(filenameExtension: "caf")?.identifier ?? "com.apple.coreaudio-format",
            byteCount: digest.size, sha256: digest.sha256, nowMs: value.createdMs, origin: .createdInsideVault)
        if !store.workspace.files.contains(where: { $0.objectName == value.object }) {
            let folder = store.workspace.folders.contains(where: { $0.id == value.folderID && $0.scope == .files }) ? value.folderID : nil
            try store.workspaceTransaction { try $0.addFile(file, folderID: folder) }
        }
        try? FileManager.default.removeItem(at: checkpointURL(value.id))
    }
    static func recoverSealed(store: VaultStore) {
        guard let lease = try? store.requireLease(), let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in urls where VaultWorkspace.isOpaqueName(url.lastPathComponent) {
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                guard size < 16_384 else { throw VaultWorkspaceError.invalidData }
                let sealed = try Data(contentsOf: url)
                let plain = try VaultCrypto.open(sealed, key: VaultCrypto.subkey(lease.key, salt: [], info: "pm-vault-capture"))
                let value = try JSONDecoder().decode(VaultCaptureCheckpoint.self, from: plain)
                guard value.id == url.lastPathComponent, VaultWorkspace.isOpaqueName(value.object) else { throw VaultWorkspaceError.invalidData }
                try complete(value, lease: lease, store: store)
            } catch {
                // Unvollständige Aufnahme (z. B. App beendet): verschlüsselt aufbewahren, nie als fertig zeigen, und nur
                // einmal melden – der Merkzettel wird beiseitegelegt statt bei jedem Öffnen erneut versucht.
                park(url)
                store.operationFailed = true
            }
        }
    }

    private static func park(_ url: URL) {
        let parked = directory.appendingPathComponent("p", isDirectory: true)
        try? FileManager.default.createDirectory(at: parked, withIntermediateDirectories: true,
                                                  attributes: [.protectionKey: FileProtectionType.complete])
        try? FileManager.default.moveItem(at: url, to: parked.appendingPathComponent(url.lastPathComponent))
    }
}

@MainActor @Observable
private final class VaultVoiceRecorder: NSObject {
    private(set) var recording = false
    private(set) var paused = false
    private(set) var seconds = 0.0
    var error: String?
    private var engine: AVAudioEngine?
    private var stream: VaultAudioStream?
    private var checkpoint: VaultCaptureCheckpoint?
    private var lease: VaultSessionLease?
    private var tapInstalled = false
    @ObservationIgnored nonisolated(unsafe) private var observers: [any NSObjectProtocol] = []
    override init() {
        super.init()
        // Sperren, Unterbrechung (Anruf) und ein entferntes Mikrofon beenden und sichern die Aufnahme. Andere
        // Routenwechsel (z. B. beim Start durch die Audio-Kategorie) nicht. AVAudioSession meldet auf beliebigen
        // Threads: Zustellung auf der Hauptwarteschlange.
        let center = NotificationCenter.default
        // Sperren wird auf dem Main Thread gemeldet und muss synchron fertig sein, bevor der Schlüssel verworfen wird.
        observers.append(center.addObserver(forName: .vaultWillLock, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) {
            [weak self] note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            MainActor.assumeIsolated { if began { self?.stop() } }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) {
            [weak self] note in
            let lost = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            MainActor.assumeIsolated { if lost { self?.stop() } }
        })
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
    func start(folderID: String?) async {
        guard !recording else { return }
        do {
            let lease = try VaultStore.shared.requireLease()
            guard await AVAudioApplication.requestRecordPermission() else { error = L("vault2_microphone_permission"); return }
            guard VaultStore.shared.accepts(lease) else { return }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement); try session.setActive(true)
            let engine = AVAudioEngine()
            let input = engine.inputNode, format = input.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.commonFormat == .pcmFormatFloat32 else { throw VaultWorkspaceError.invalidData }
            let value = VaultCaptureCheckpoint(id: UUID().uuidString, object: UUID().uuidString,
                name: VaultWorkspaceMessages.fileName("Audio", extension: "caf"), createdMs: VaultStore.shared.nowMs, folderID: folderID)
            let stream = try VaultAudioStream(object: value.object, sampleRate: format.sampleRate, lease: lease)
            self.engine = engine; self.stream = stream; self.checkpoint = value; self.lease = lease
            try VaultCaptureRecovery.begin(value, lease: lease)
            input.installTap(onBus: 0, bufferSize: 4096, format: format, block: VaultAudioStream.tap(stream))
            tapInstalled = true
            engine.prepare(); try engine.start()
            recording = true; paused = false; VaultStore.shared.touch()
        } catch { self.error = VaultWorkspaceMessages.error(error); stop(); try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
    func pauseOrResume() {
        guard recording, let engine else { return }
        do {
            if paused { try engine.start() } else { engine.pause() }
            paused.toggle(); VaultStore.shared.touch()
        } catch { self.error = VaultWorkspaceMessages.error(error); stop() }
    }
    func tick() {
        seconds = stream?.duration ?? seconds
        if stream?.hasFailed == true { error = L("vault2_operation_failed"); stop() }
    }
    func stop() {
        guard let engine else { return }
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        self.engine = nil; recording = false; paused = false
        defer {
            stream = nil; checkpoint = nil; lease = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        guard let stream, let checkpoint, let lease else { return }
        if stream.discardIfEmpty() { VaultCaptureRecovery.discardEmptyCheckpoint(checkpoint); return }
        do {
            _ = try stream.finish()
            try VaultCaptureRecovery.complete(checkpoint, lease: lease, store: VaultStore.shared)
        } catch {
            // Any recoverable recording remains encrypted with its checkpoint, also after vault lock.
            self.error = VaultWorkspaceMessages.error(error); VaultStore.shared.operationFailed = true
        }
    }
}

struct VaultVoiceRecorderView: View {
    let folderID: String?
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = VaultVoiceRecorder()
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "waveform").font(.system(size: 56)).accessibilityHidden(true)
                Text(verbatim: String(format: "%02d:%02d", Int(recorder.seconds) / 60, Int(recorder.seconds) % 60))
                    .font(.largeTitle.monospacedDigit()).accessibilityLabel(L("vault2_recorded_time"))
                Text(L("vault2_recording_explanation")).multilineTextAlignment(.center)
                if recorder.recording {
                    Button(L(recorder.paused ? "vault2_resume" : "vault2_pause")) { recorder.pauseOrResume() }.buttonStyle(.bordered)
                    Button(L("vault2_stop_save"), systemImage: "stop.fill") { recorder.stop() }.buttonStyle(.borderedProminent)
                } else {
                    Button(L("vault2_record"), systemImage: "mic") { Task { await recorder.start(folderID: folderID) } }.buttonStyle(.borderedProminent)
                }
            }.padding()
            .navigationTitle(L("vault2_record"))
            .toolbar { Button(L("done")) { recorder.stop(); dismiss() } }
            .task {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                    recorder.tick()
                }
            }
            .onDisappear { recorder.stop() }
            .vaultWorkspaceError($recorder.error)
        }
    }
}
