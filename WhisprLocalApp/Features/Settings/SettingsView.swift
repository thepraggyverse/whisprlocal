import SwiftUI

/// Root of the Settings tab. M2 scope: just the Models row — everything
/// else lands in M5–M6. Each row is a `NavigationLink` so the deeper
/// screens can live in their own files without this root growing.
struct SettingsView: View {

    @Environment(ModelStore.self) private var modelStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ModelPickerView()
                    } label: {
                        modelsRow
                    }
                } header: {
                    Text("Speech-to-Text")
                } footer: {
                    Text("Models run entirely on-device. Download once, use offline forever.")
                }

                Section("Privacy") {
                    Label("100% on-device", systemImage: "lock.shield.fill")
                        .foregroundStyle(.green)
                    Text("No analytics. No crash SDK. No cloud fallback.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var modelsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Model")
            HStack(spacing: 6) {
                Text(modelStore.selectedEntry?.displayName ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let id = modelStore.selectedEntry?.id,
                   modelStore.state(for: id) == .completed {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(PreviewFixtures.modelStore)
}
