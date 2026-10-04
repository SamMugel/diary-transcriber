import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

// AI:
//   what: SettingsViewModel manages user preferences (output folder, mic, API key)
//   why:  specs/ui.md requires @MainActor @Observable view-model injected into SettingsView;
//         API key stored in Keychain, output folder in UserDefaults
//   ref:  specs/ui.md SettingsView, D-0004, specs/transcription.md Security

@MainActor
@Observable
public final class SettingsViewModel {

    private static let outputFolderKey = "com.compactifai.diarytranscriber.outputFolder"
    private static let micIDKey = "com.compactifai.diarytranscriber.micID"

    var outputFolder: String {
        get {
            UserDefaults.standard.string(forKey: Self.outputFolderKey)
                ?? "~/Documents/Diary"
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.outputFolderKey) }
    }

    var micID: String {
        get {
            UserDefaults.standard.string(forKey: Self.micIDKey) ?? ""
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.micIDKey) }
    }

    var transcriptionSettings = TranscriptSettings()

    var apiKey: String {
        get { transcriptionSettings.apiKey ?? "" }
        set { transcriptionSettings.apiKey = newValue.isEmpty ? nil : newValue }
    }

    var availableMics: [(id: String, name: String)] {
        #if canImport(AVFoundation)
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        return session.devices.map { device in
            (device.uniqueID, device.localizedName)
        }
        #else
        return []
        #endif
    }

    public init() {}
}
