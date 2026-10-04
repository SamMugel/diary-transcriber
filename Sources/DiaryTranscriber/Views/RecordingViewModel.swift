import SwiftUI

// AI:
//   what: RecordingViewModel — @MainActor observable backing RecordingView
//   why:  specs/ui.md: liveTranscript, elapsed, isFinalizing state;
//         orchestrates AudioRecorder and SpeechTranscriber
//   ref:  specs/ui.md RecordingViewModel, D-0004, D-0008

@MainActor
@Observable
public final class RecordingViewModel {

    public var liveTranscript: String = ""
    public var elapsed: Double = 0
    public var isFinalizing = false

    private let recorder: AudioRecorder
    private(set) var handle: RecordingHandle?
    private var timer: Task<Void, Never>?

    public init(recorder: AudioRecorder = AudioRecorder()) {
        self.recorder = recorder
    }

    public var isRecording: Bool { handle != nil && !isFinalizing }

    public func start() async {
        do {
            liveTranscript = ""
            elapsed = 0
            isFinalizing = false
            handle = try await recorder.start()
            startTimer()
        } catch {
            // Surface error to the view for display.
            liveTranscript = "Error: \(error.localizedDescription)"
        }
    }

    public func stop() async {
        guard handle != nil, !isFinalizing else { return }
        isFinalizing = true
        cancelTimer()

        do {
            let audioURL = try await recorder.stop()
            // In v1, transcription is a separate step.
            // The live transcript from SpeechTranscriber would be finalized here.
            _ = audioURL
        } catch {
            liveTranscript = "Error: \(error.localizedDescription)"
        }

        isFinalizing = false
        handle = nil
    }

    func appendTranscript(text: String) {
        if liveTranscript.isEmpty {
            liveTranscript = text
        } else {
            liveTranscript += " " + text
        }
    }

    // MARK: - Private: Timer

    private func startTimer() {
        timer?.cancel()
        timer = Task { @MainActor in
            while !Task.isCancelled {
                elapsed = handle?.elapsed() ?? 0
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
    }
}
