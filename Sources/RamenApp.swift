import SwiftUI

@main
struct RamenApp: App {
    var body: some Scene {
        WindowGroup {
            RamenView()
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
