import SwiftUI

@main
struct MCLauncherApp: App {
    @StateObject private var model = LauncherModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.accounts)
                .environmentObject(model.settings)
                .preferredColorScheme(.dark)
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = model.settings.settings.preventSleep
                }
        }
    }
}
