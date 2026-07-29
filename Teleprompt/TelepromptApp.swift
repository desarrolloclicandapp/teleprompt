import SwiftUI

@main
struct TelepromptApp: App {
    @StateObject private var library = ScriptLibrary()
    @StateObject private var drive = DriveSyncCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(drive)
                .preferredColorScheme(.dark)
        }
    }
}
