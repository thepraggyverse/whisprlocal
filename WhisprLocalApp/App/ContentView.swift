import SwiftUI

/// App shell. Hosts the two tabs M2 ships with: Record (the M1 screen,
/// extended to show transcripts) and Settings (model picker). M6 pulls
/// History into a third tab.
struct ContentView: View {
    var body: some View {
        TabView {
            RecordView()
                .tabItem {
                    Label("Record", systemImage: "mic.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }
}

#Preview {
    ContentView()
        .environment(PreviewFixtures.modelStore)
        .environment(PreviewFixtures.transcriptionStore)
}
