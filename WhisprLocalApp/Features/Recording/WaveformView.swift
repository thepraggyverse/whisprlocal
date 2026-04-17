import SwiftUI

/// Simple N-bar waveform driven by a fixed-size window of recent normalized
/// levels (0…1). The parent keeps a ring of `barCount` samples fed by
/// `AudioCaptureService.levelStream` and passes it here each tick.
///
/// Respects `accessibilityReduceMotion` per PROJECT_SPEC.md §7.
struct WaveformView: View {

    let levels: [Float]
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let barCount = 24
    private let maxBarHeight: CGFloat = 56
    private let minBarHeight: CGFloat = 4
    private let barWidth: CGFloat = 4
    private let spacing: CGFloat = 3

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<Self.barCount, id: \.self) { idx in
                let level = idx < levels.count ? levels[idx] : 0
                Capsule()
                    .fill(.tint.opacity(isActive ? 1.0 : 0.35))
                    .frame(width: barWidth, height: height(for: level))
                    .animation(tickAnimation, value: level)
            }
        }
        .frame(height: maxBarHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isActive ? "Recording audio waveform" : "Waveform idle")
    }

    private func height(for level: Float) -> CGFloat {
        minBarHeight + CGFloat(level) * (maxBarHeight - minBarHeight)
    }

    private var tickAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.12)
    }
}

#Preview("Idle") {
    WaveformView(levels: Array(repeating: 0, count: WaveformView.barCount), isActive: false)
        .padding()
}

#Preview("Active") {
    WaveformView(
        levels: (0..<WaveformView.barCount).map { _ in Float.random(in: 0.1...0.9) },
        isActive: true
    )
    .padding()
}
