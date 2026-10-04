import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif
import Observation

// AI:
//   what: RecordingHandle exposes live recording state (elapsed time) and a stop callback
//   why:  specs/ui.md RecordingView observes elapsed time; the view-model calls stop()
//         to finalize the recording; this is the observable bridge between actor and UI
//   ref:  specs/recording.md RecordingHandle

public struct RecordingHandle: Sendable {
    public let id: UUID
    public let startedAt: Date
    public let outputURL: URL

    public init(id: UUID = UUID(), startedAt: Date, outputURL: URL) {
        self.id = id
        self.startedAt = startedAt
        self.outputURL = outputURL
    }

    public func elapsed() -> Double {
        Date().timeIntervalSince(startedAt)
    }
}
