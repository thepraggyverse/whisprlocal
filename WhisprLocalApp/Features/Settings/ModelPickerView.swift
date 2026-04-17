import SwiftUI

/// Lists every `ModelEntry` in the catalog with a per-row action that
/// reflects the current `ModelStore.DownloadState` (idle/downloading/
/// completed/failed). Selection is explicit via the "Use" button so
/// one bad tap doesn't re-download hundreds of MB.
struct ModelPickerView: View {

    @Environment(ModelStore.self) private var modelStore

    var body: some View {
        List {
            ForEach(modelStore.catalog.entries) { entry in
                ModelRow(entry: entry)
            }
        }
        .navigationTitle("Model")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ModelRow: View {

    @Environment(ModelStore.self) private var modelStore
    let entry: ModelEntry

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(.body.weight(.medium))
                    if modelStore.selectedModelId == entry.id {
                        Label("Selected", systemImage: "checkmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.green)
                            .accessibilityLabel("Selected")
                    }
                }
                Text(summaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            actionView
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var summaryLine: String {
        let size = Self.byteFormatter.string(fromByteCount: entry.sizeBytes)
        return "\(size) • \(entry.language.rawValue)"
    }

    @ViewBuilder
    private var actionView: some View {
        switch modelStore.state(for: entry.id) {
        case .idle:
            Button("Download") {
                Task { await modelStore.download(entry: entry) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case .downloading(let fraction):
            VStack(spacing: 4) {
                ProgressView(value: fraction)
                    .frame(width: 80)
                Text("\(Int(fraction * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Downloading \(Int(fraction * 100)) percent")

        case .completed:
            if modelStore.selectedModelId != entry.id {
                Button("Use") {
                    modelStore.select(modelId: entry.id)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Text("In use")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .failed(let reason):
            VStack(alignment: .trailing, spacing: 4) {
                Label("Failed", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.orange)
                Button("Retry") {
                    Task { await modelStore.download(entry: entry) }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .accessibilityLabel("Download failed: \(reason). Tap Retry.")
        }
    }
}

#Preview {
    NavigationStack {
        ModelPickerView()
    }
    .environment(PreviewFixtures.modelStore)
}
