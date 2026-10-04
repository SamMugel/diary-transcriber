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

    // AI: production Keychain coordinates for the OpenAI API key; mirror KeychainHelper's private service/account
    //     so default args are explicit and tests inject their own service instead / PRD 30
    private static let keychainService = "com.compactifai.diarytranscriber"
    private static let keychainAccount = "api-key"

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

    // AI: read-only apiKey getter — never written from the view loop; SettingsView buffers keystrokes
    //     in a @State and calls commitAPIKey(_:) only on .onSubmit / .onDisappear / Save,
    //     eliminating per-keystroke SecItemDelete → SecItemAdd churn that froze typing / PRD 30
    var apiKey: String {
        KeychainHelper.loadAPIKey() ?? ""
    }

    // AI: test-friendly load that mirrors commitAPIKey's optional service/account overloads so the
    //     test suite can read back under its own service without touching the production api-key entry / PRD 30
    func apiKey(service: String, account: String) -> String {
        KeychainHelper.loadAPIKey(service: service, account: account) ?? ""
    }

    // AI: single explicit commit point for the SecureField buffer; writes to Keychain exactly once
    //     per user action, not per character; empty string removes the key from Keychain.
    //     Production overload resolves to the com.compactifai.diarytranscriber service; the
    //     test suite uses the parameterized overload with a test-specific service so CI never
    //     collides with the user's real api-key entry / PRD 30
    func commitAPIKey(_ value: String) {
        commitAPIKey(value, service: Self.keychainService, account: Self.keychainAccount)
    }

    func commitAPIKey(_ value: String, service: String, account: String) {
        if value.isEmpty {
            KeychainHelper.deleteAPIKey(service: service, account: account)
        } else {
            try? KeychainHelper.saveAPIKey(value, service: service, account: account)
        }
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
