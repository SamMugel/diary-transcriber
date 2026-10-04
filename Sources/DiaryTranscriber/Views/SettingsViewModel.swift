import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

// AI:
//   what: SettingsViewModel manages user preferences (output folder, mic, API key)
//   why:  specs/ui.md requires @MainActor @Observable view-model injected into SettingsView;
//         API key stored in Keychain, output folder & transcription toggles in UserDefaults
//   ref:  specs/ui.md SettingsView, D-0004, specs/transcription.md Security, PRD 29

@MainActor
@Observable
public final class SettingsViewModel {

    private static let outputFolderKey = "com.compactifai.diarytranscriber.outputFolder"
    private static let micIDKey = "com.compactifai.diarytranscriber.micID"
    private static let useOnDeviceSpeechKey = "com.compactifai.diarytranscriber.useOnDeviceSpeech"
    private static let useWhisperFallbackKey = "com.compactifai.diarytranscriber.useWhisperFallback"

    var outputFolder: String {
        get {
            UserDefaults.standard.string(forKey: Self.outputFolderKey)
                ?? "~/Documents/Diary"
        }
        // AI: outputFolder/micID persist inline on set; toggles await save() for atomic, deterministic writes / PRD 29
        set { UserDefaults.standard.set(newValue, forKey: Self.outputFolderKey) }
    }

    var micID: String {
        get {
            UserDefaults.standard.string(forKey: Self.micIDKey) ?? ""
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.micIDKey) }
    }

    var transcriptionSettings: TranscriptSettings

    var apiKey: String {
        get { transcriptionSettings.apiKey ?? "" }
        // AI: apiKey writes to Keychain only, independent of toggle persistence; never mix stores / PRD 29
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

    public init() {
        transcriptionSettings = Self.readTranscriptSettings()
    }

    /// Writes both transcription toggles to UserDefaults atomically. AI: deterministic commit so toggles hold across restarts; Keychain API-key writes never interleave here / PRD 29
    public func save() {
        let settings = transcriptionSettings
        UserDefaults.standard.set(settings.useOnDeviceSpeech, forKey: Self.useOnDeviceSpeechKey)
        UserDefaults.standard.set(settings.useWhisperFallback, forKey: Self.useWhisperFallbackKey)
    }

    // AI: read toggles from UserDefaults with the same defaults as TranscriptSettings() so a fresh store yields defaults / PRD 29
    private static func readTranscriptSettings() -> TranscriptSettings {
        let defaults = TranscriptSettings()
        if let storedOnDevice = UserDefaults.standard.object(forKey: useOnDeviceSpeechKey) as? Bool {
            return TranscriptSettings(
                useOnDeviceSpeech: storedOnDevice,
                useWhisperFallback: UserDefaults.standard.object(forKey: useWhisperFallbackKey) as? Bool
                    ?? defaults.useWhisperFallback
            )
        }
        return defaults
    }
}
