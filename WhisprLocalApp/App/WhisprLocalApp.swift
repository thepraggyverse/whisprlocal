import SwiftUI

/// Entry point for the main WhisprLocal iOS app. The `@main` struct owns
/// the single `AppServices` graph and injects its `@Observable` stores
/// into the view tree. Everything interesting happens elsewhere — this
/// file stays thin on purpose.
@main
struct WhisprLocalApp: App {

    @State private var services = AppServices.makeProduction()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(services.modelStore)
                .environment(services.transcriptionStore)
                .task {
                    await services.start()
                }
        }
    }
}
