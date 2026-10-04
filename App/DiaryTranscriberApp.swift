import SwiftUI
import DiaryTranscriberCore

@main
struct DiaryTranscriberApp: App {

    let store: DiaryStore = {
        let folder = outputFolderFromSettings()
        return DiaryStore(folder: URL(filePath: folder))
    }()

    var body: some Scene {
        // AI: PRD 11 — default window 900×660, minimum 720×540 enforced by the
        //     ContentView frame; .windowResizability(.contentMinSize) makes the
        //     min-size frame on the content authoritative so the window cannot be
        //     resized below it.
        WindowGroup {
            ContentView(store: store)
        }
        .defaultSize(width: 900, height: 660)
        .windowResizability(.contentMinSize)
    }

    /// Read the output folder from UserDefaults (same key as SettingsViewModel).
    /// On first launch, defaults to `~/Documents/Diary`.
    private nonisolated static func outputFolderFromSettings() -> String {
        let key = "com.compactifai.diarytranscriber.outputFolder"
        let saved = UserDefaults.standard.string(forKey: key)
        if let saved, !saved.isEmpty {
            return resolveHome(saved)
        }

        // Default: ~/Documents/Diary
        let home = NSHomeDirectory()
        return "\(home)/Documents/Diary"
    }

    /// Resolve `~` in a path to the actual home directory.
    private nonisolated static func resolveHome(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        return NSHomeDirectory() + String(path.dropFirst())
    }
}
