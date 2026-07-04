import SwiftUI
import SwiftData

@main
struct DramaAppApp: App {
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
        }
        .modelContainer(for: FavoriteDrama.self)
    }
}
