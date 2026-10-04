import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

// AI:
//   what: PermissionManager checks and requests microphone access on macOS
//   why:  AVFoundation requires explicit permission before audio capture;
//         this wrapper converts the callback-based requestAccess to async/await
//   ref:  specs/recording.md Permission flow, D-0002

@MainActor
enum PermissionManager {

    static func checkMicrophonePermission() async throws -> Bool {
        #if canImport(AVFoundation)
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            return true

        case .notDetermined:
            return try await requestMicrophoneAccess()

        case .denied, .restricted:
            throw RecorderError.permissionDenied(
                "Microphone access was denied. Grant access in System Settings → Privacy & Security → Microphone."
            )

        @unknown default:
            throw RecorderError.permissionDenied(
                "Microphone authorization status is unknown on this system."
            )
        }
        #else
        throw RecorderError.permissionDenied("AVFoundation is not available on this platform.")
        #endif
    }

    #if canImport(AVFoundation)
    private static func requestMicrophoneAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(throwing: RecorderError.permissionDenied(
                        "Microphone access was denied in the permission prompt."
                    ))
                }
            }
        }
    }
    #endif
}
