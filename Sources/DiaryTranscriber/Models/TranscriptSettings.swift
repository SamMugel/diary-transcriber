import Foundation

// AI:
//   what: TranscriptSettings stores user preferences for transcription engines
//   why:  specs/ui.md SettingsView requires Speech toggle, Whisper fallback toggle,
//         and API key; these control TranscriptionService fallback behavior
//   ref:  specs/transcription.md, specs/ui.md SettingsView

struct TranscriptSettings: Codable {
    var useOnDeviceSpeech: Bool = true
    var useWhisperFallback: Bool = true

    var apiKey: String? {
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
