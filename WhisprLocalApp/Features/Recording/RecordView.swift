import SwiftUI
import UIKit

/// M1 record screen. Composes permission flow + AudioCaptureService +
/// WaveformView + RecordButton.
///
/// The brand badge ("100% on-device") lives in the header here per
/// PROJECT_SPEC.md §7 — visible from first launch, so the privacy promise
/// is never an afterthought.
@MainActor
struct RecordView: View {

    @State private var service = AudioCaptureService()
    @State private var permissionStatus: RecordingPermissionStatus = .notDetermined
    @State private var levels: [Float] = Array(repeating: 0, count: WaveformView.barCount)
    @State private var lastWrittenURL: URL?
    @State private var errorMessage: String?

    @Environment(\.openURL) private var openURL

    private let permission: RecordingPermissionAuthority = AVRecordingPermissionAuthority()

    var body: some View {
        VStack(spacing: 24) {
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

            statusArea
                .frame(minHeight: 48)
        }
        .padding()
        .task(id: "permission-bootstrap") {
            permissionStatus = permission.currentStatus
        }
        .task(id: "level-stream") {
            for await level in service.levelStream {
                pushLevel(level)
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
        } else if permissionStatus == .denied {
            deniedGuidance
        } else if let url = lastWrittenURL {
            VStack(spacing: 4) {
                Text("Saved to inbox/")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(url.lastPathComponent)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
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
        let currentPermission: RecordingPermissionStatus
        if permissionStatus == .notDetermined {
            currentPermission = await permission.request()
            permissionStatus = currentPermission
        } else {
            currentPermission = permissionStatus
        }

        guard currentPermission == .granted else { return }

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
}
