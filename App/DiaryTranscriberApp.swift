import SwiftUI
import DiaryTranscriberCore

@main
struct DiaryTranscriberApp: App {

    // AI: PRD #28 — a single AppEnvironment owns the shared DiaryStore, SettingsViewModel, and
    //     TranscriptionService (which is built once at init from the Keychain API key). Delivered
    //     to the SwiftUI hierarchy via .environment(env) so ContentView and its sheets resolve the
    //     shared services through @Environment(AppEnvironment.self) instead of ad-hoc threading.
    @MainActor private let env: AppEnvironment = AppEnvironment()

    var body: some Scene {
        // AI: PRD 11 — default window 900×660, minimum 720×540 enforced by the
        //     ContentView frame; .windowResizability(.contentMinSize) makes the
        //     min-size frame on the content authoritative so the window cannot be
        //     resized below it.
        WindowGroup {
            ContentView()
                .environment(env)
        }
        .defaultSize(width: 900, height: 660)
        .windowResizability(.contentMinSize)
    }
}
