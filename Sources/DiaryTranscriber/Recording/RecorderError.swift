import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

// AI:
//   what: Error type for recording failures
//   why:  Typed errors per Swift error handling rule; the UI maps RecorderError
//         to specific user-facing messages and recovery actions
//   ref:  specs/recording.md error table

enum RecorderError: LocalizedError {
    case permissionDenied(String)
    case noDevice
    case cannotAddOutput
    case recordingFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let detail):
            "Microphone access denied: \(detail)"
        case .noDevice:
            "No audio input device found."
        case .cannotAddOutput:
            "Recording session rejected the output configuration."
        case .recordingFailed(let underlying):
            "Recording failed: \(underlying.localizedDescription)"
        }
    }
}
