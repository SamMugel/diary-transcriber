import Foundation

// AI:
//   what: TranscriptSettings stores user preferences for transcription engines
//   why:  specs/ui.md SettingsView requires Speech toggle, Whisper fallback toggle,
//         and API key; these control TranscriptionService fallback behavior
//   ref:  specs/transcription.md, specs/ui.md SettingsView

public struct TranscriptSettings: Codable, Equatable, Sendable {
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
        // AI: read-only getter — setter removed so SecureField typing never triggers per-keystroke
        //     SecItemDelete → SecItemAdd churn; SettingsViewModel.commitAPIKey is the only write path,
        //     invoked on .onSubmit / .onDisappear only, never on each character / PRD 30
        get { KeychainHelper.loadAPIKey() }
    }
}
