import Foundation

// AI:
//   what: AudioRecorderProtocol — abstraction over the concrete AudioRecorder actor
//   why:  PRD #35 — end-to-end pipeline tests must drive RecordingViewModel with a stub
//         recorder that returns a fixed .m4a fixture URL and never opens the microphone.
//         Without a protocol, RecordingViewModel holds a concrete `AudioRecorder` actor
//         and CI has no seam to inject a fake. The protocol preserves the public API
//         surface of AudioRecorder (start / stop / currentElapsedTime) verbatim so the
//         concrete actor conforms without signature changes; production callers continue
//         to construct `AudioRecorder()` and tests inject a stub conforming to this same
//         shape.
//   ref:  PRD 35-end-to-end-record-pipeline-tests, specs/recording.md AudioRecorder API

public protocol AudioRecorderProtocol: Sendable {
    /// Begins capture and returns a live handle. Throws on permission denial or
    /// a failure to configure the AV capture session.
    func start() async throws -> RecordingHandle

    /// Halts capture and returns the URL of the recorded `.m4a` file. Throws
    /// `RecorderError.notRecording` if `start()` was never called.
    func stop() async throws -> URL

    /// Elapsed seconds since the capture began, or 0 when not recording.
    /// `async` so protocol-typed callers cross actor isolation uniformly.
    func currentElapsedTime() async -> Double
}
