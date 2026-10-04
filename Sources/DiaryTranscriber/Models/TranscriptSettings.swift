import Foundation

// AI:
//   what: TranscriptSettings stores user preferences for transcription engines
//   why:  specs/ui.md SettingsView requires Speech toggle, Whisper fallback toggle,
//         and API key; these control TranscriptionService fallback behavior
//   ref:  specs/transcription.md, specs/ui.md SettingsView

public struct TranscriptSettings: Codable {
    public var useOnDeviceSpeech: Bool = true
    public var useWhisperFallback: Bool = true

    public init(
        useOnDeviceSpeech: Bool = true,
        useWhisperFallback: Bool = true
    ) {
        self.useOnDeviceSpeech = useOnDeviceSpeech
        self.useWhisperFallback = useWhisperFallback
    }

    public var apiKey: String? {
        get { KeychainHelper.loadAPIKey() }
        set {
            if let newValue, !newValue.isEmpty {
                try? KeychainHelper.saveAPIKey(newValue)
            } else {
                KeychainHelper.deleteAPIKey()
            }
        }
    }
}
