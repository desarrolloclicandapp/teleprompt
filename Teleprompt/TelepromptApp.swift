import SwiftUI

@main
struct TelepromptApp: App {
    @StateObject private var library = ScriptLibrary()
    @StateObject private var drive = DriveSyncCoordinator()
    @StateObject private var purchaseManager = PurchaseManager()

    var body: some Scene {
        WindowGroup {
            MonetizationGateView {
                RootView()
            }
                .environmentObject(library)
                .environmentObject(drive)
                .environmentObject(purchaseManager)
                .preferredColorScheme(.dark)
        }
    }
}
