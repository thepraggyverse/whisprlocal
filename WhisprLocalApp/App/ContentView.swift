import SwiftUI

/// App-level root view. Currently renders the M1 record screen directly;
/// M2 will introduce a tab bar (record / history / settings) and this view
/// is the natural home for that shell.
struct ContentView: View {
    var body: some View {
        RecordView()
    }
}

#Preview {
    ContentView()
}
