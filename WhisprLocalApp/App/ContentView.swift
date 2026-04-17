import SwiftUI

/// Placeholder landing view for the main app at M0.
///
/// The persistent "on-device" badge is part of the brand promise
/// (PROJECT_SPEC.md §7) and lands here at M0 even before there's anything
/// to transcribe — visible from day one so the guarantee is never an
/// afterthought.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("WhisprLocal")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("On-device voice transcription")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label("100% on-device", systemImage: "lock.shield.fill")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.tint.opacity(0.15), in: Capsule())
                .padding(.top, 8)
                .accessibilityLabel("Runs 100 percent on device")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
