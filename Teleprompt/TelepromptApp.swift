import SwiftUI

@main
struct TelepromptApp: App {
    @StateObject private var library = ScriptLibrary()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .preferredColorScheme(.dark)
        }
    }
}

