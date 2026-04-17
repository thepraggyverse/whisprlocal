import SwiftUI
import UIKit

/// Record screen. Composes permission flow + `AudioCaptureService` +
/// `WaveformView` + `RecordButton`, and — at M2 — the transcript surface
/// sourced from `TranscriptionStore`.
///
/// The brand badge ("100% on-device") lives in the header here per
/// PROJECT_SPEC.md §7 — visible from first launch, so the privacy
/// promise is never an afterthought.
@MainActor
struct RecordView: View {

    @State private var service = AudioCaptureService()
    @State private var permissionGate: RecordPermissionGate
    @State private var levels: [Float] = Array(repeating: 0, count: WaveformView.barCount)
    @State private var lastWrittenURL: URL?
    @State private var errorMessage: String?
    @State private var copyConfirmationVisible = false

    @Environment(ModelStore.self) private var modelStore
    @Environment(TranscriptionStore.self) private var transcriptionStore
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    init(permissionAuthority: RecordingPermissionAuthority = AVRecordingPermissionAuthority()) {
        _permissionGate = State(initialValue: RecordPermissionGate(authority: permissionAuthority))
    }

    var body: some View {
        VStack(spacing: 20) {
            header

            WaveformView(
                levels: levels,
                isActive: service.state == .recording
            )

            RecordButton(
                isRecording: service.state == .recording,
                isBusy: service.state == .finalizing,
                action: { Task { await handleRecordTap() } }
            )
            .disabled(!modelStore.isReadyForTranscription)

            statusArea
                .frame(minHeight: 44)

            transcriptArea
        }
        .padding()
        .task(id: "level-stream") {
            for await level in service.levelStream {
                pushLevel(level)
            }
        }
        // Re-read the live system permission every time the scene returns
        // to .active. Without this, a user who denied the mic, tapped
        // "Open Settings", granted the mic in iOS Settings, and returned
        // would stay stuck on the cached .denied status — beginRecording's
        // guard would fail silently and lock them out indefinitely.
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            if newPhase == .active {
                permissionGate.refreshFromSystem()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("WhisprLocal")
                .font(.largeTitle.bold())

            Label("100% on-device", systemImage: "lock.shield.fill")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.tint.opacity(0.15), in: Capsule())
                .accessibilityLabel("Runs 100 percent on device")
        }
    }

    // MARK: - Status area

    @ViewBuilder
    private var statusArea: some View {
        if let error = errorMessage {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        } else if permissionGate.status == .denied {
            deniedGuidance
        } else if !modelStore.isReadyForTranscription {
            modelNotReadyGuidance
        } else if let url = lastWrittenURL,
                  transcriptionStore.latest?.audioURL != url {
            VStack(spacing: 4) {
                ProgressView()
                Text("Transcribing…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else if transcriptionStore.latest == nil {
            Text("Tap the mic to start recording.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var deniedGuidance: some View {
        VStack(spacing: 8) {
            Text("Microphone access is off.")
                .font(.footnote.bold())
            Text("Turn it on in Settings to record.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var modelNotReadyGuidance: some View {
        VStack(spacing: 6) {
            Text("Download a model to get started.")
                .font(.footnote.bold())
            Text("Go to Settings → Model and pick one.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Transcript area

    @ViewBuilder
    private var transcriptArea: some View {
        if let outcome = transcriptionStore.latest {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Latest transcript")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = outcome.rawText
                        copyConfirmationVisible = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            copyConfirmationVisible = false
                        }
                    } label: {
                        Label(
                            copyConfirmationVisible ? "Copied" : "Copy",
                            systemImage: copyConfirmationVisible ? "checkmark" : "doc.on.doc"
                        )
                        .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(copyConfirmationVisible ? "Copied to clipboard" : "Copy transcript")
                }

                Text(outcome.rawText)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 4)
            .transition(.opacity)
        }
    }

    // MARK: - Actions

    private func handleRecordTap() async {
        errorMessage = nil

        switch service.state {
        case .recording:
            await finishRecording()
        case .finalizing:
            return
        case .idle:
            await beginRecording()
        }
    }

    private func beginRecording() async {
        let resolved = await permissionGate.requestIfNeeded()
        guard resolved == .granted else { return }

        do {
            try await service.start()
            levels = Array(repeating: 0, count: WaveformView.barCount)
            lastWrittenURL = nil
        } catch {
            errorMessage = "Couldn't start recording: \(error.localizedDescription)"
        }
    }

    private func finishRecording() async {
        do {
            let url = try await service.stop()
            lastWrittenURL = url
        } catch {
            errorMessage = "Recording failed: \(error.localizedDescription)"
        }
    }

    private func pushLevel(_ level: Float) {
        var next = levels
        next.removeFirst()
        next.append(level)
        levels = next
    }
}

#Preview {
    RecordView()
        .environment(PreviewFixtures.modelStore)
        .environment(PreviewFixtures.transcriptionStore)
}
