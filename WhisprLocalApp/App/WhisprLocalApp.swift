import SwiftUI

/// Entry point for the main WhisprLocal iOS app.
///
/// Intentionally minimal at M0 — the SwiftUI shell exists so the project
/// compiles and Xcode has a `@main` to anchor onto. Real UI arrives at M1
/// (recording), M2 (transcription), M3 (polish), and M6 (settings).
@main
struct WhisprLocalApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
