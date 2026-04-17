import SwiftUI

/// Large circular record / stop control. SF-Symbol-only per PROJECT_SPEC.md §7.
///
/// At M1 this is a plain tap-to-toggle; the push-to-talk variant from
/// PROJECT_SPEC.md §5.1 lands alongside the user-preference setting at M6.
struct RecordButton: View {

    let isRecording: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(tint)

                if isBusy {
                    ProgressView()
                        .controlSize(.large)
                }
            }
        }
        .frame(width: 120, height: 120)
        .disabled(isBusy)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    // MARK: - Presentation

    private var iconName: String {
        if isBusy { return "circle.dotted" }
        return isRecording ? "stop.circle.fill" : "mic.circle.fill"
    }

    private var tint: Color {
        if isBusy { return .secondary }
        return isRecording ? .red : .accentColor
    }

    private var accessibilityLabel: String {
        if isBusy { return "Finalizing recording" }
        return isRecording ? "Stop recording" : "Start recording"
    }

    private var accessibilityHint: String {
        if isBusy { return "Writing the recording to disk" }
        return isRecording
            ? "Stops recording and saves the audio file on device"
            : "Starts recording audio entirely on your device"
    }
}

#Preview("Idle") {
    RecordButton(isRecording: false, isBusy: false) {}
        .padding()
}

#Preview("Recording") {
    RecordButton(isRecording: true, isBusy: false) {}
        .padding()
}

#Preview("Busy") {
    RecordButton(isRecording: false, isBusy: true) {}
        .padding()
}
