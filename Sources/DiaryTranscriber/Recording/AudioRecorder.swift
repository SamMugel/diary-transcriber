import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

// AI:
//   what: AudioRecorder actor captures microphone audio to an .m4a (AAC) file
//   why:  D-0002 audio recording first; AVCaptureSession + AVCaptureAudioFileOutput
//         produce AAC-encoded .m4a files as required by specs/recording.md
//   ref:  specs/recording.md AudioRecorder API, D-0002, D-0003

public actor AudioRecorder {

    private var isRecording = false
    private var currentOutputURL: URL?
    private var currentStartTime: Date?

    #if canImport(AVFoundation)
    private var captureSession: AVCaptureSession?
    private var fileOutput: AVCaptureFileOutput?
    private var recordingDelegate: RecordingOutputDelegate?
    #endif

    // MARK: - Lifecycle

    public init() {}

    // MARK: - Public API

    public func start() async throws -> RecordingHandle {
        guard !isRecording else {
            throw RecorderError.recordingFailed(underlying: NSError(
                domain: "AudioRecorder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Recording already in progress."]
            ))
        }

        let permissionGranted = try await checkPermission()
        guard permissionGranted else {
            throw RecorderError.permissionDenied("Microphone permission was denied.")
        }

        let url = Self.makeOutputURL()
        try Self.ensureParentDirectory(url)

        try await beginCapture(url: url)

        isRecording = true
        currentOutputURL = url
        currentStartTime = Date()

        return RecordingHandle(startedAt: Date(), outputURL: url)
    }

    public func stop() async throws -> URL {
        guard isRecording, let url = currentOutputURL else {
            // Idempotent: if not recording, return an empty URL (no-op).
            return URL(fileURLWithPath: "")
        }

        try await endCapture()

        isRecording = false
        currentOutputURL = nil
        currentStartTime = nil

        return url
    }

    public func currentElapsedTime() -> Double {
        guard isRecording, let start = currentStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    // MARK: - Private: Permission

    private func checkPermission() async throws -> Bool {
        let granted = try await PermissionManager.checkMicrophonePermission()
        return granted
    }

    // MARK: - Private: Capture session

    #if canImport(AVFoundation)
    private func beginCapture(url: URL) async throws {
        let session = AVCaptureSession()

        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw RecorderError.noDevice
        }

        let input = try AVCaptureDeviceInput(device: device)
        session.addInput(input)

        let output = AVCaptureAudioFileOutput()

        guard session.canAddOutput(output) else {
            throw RecorderError.cannotAddOutput
        }
        session.addOutput(output)

        let delegate = RecordingOutputDelegate()

        recordingDelegate = delegate
        captureSession = session
        fileOutput = output

        // Clean up any existing file.
        try? FileManager.default.removeItem(at: url)

        session.startRunning()
        output.startRecording(to: url, recordingDelegate: delegate)
    }

    private func endCapture() async throws {
        guard let output = fileOutput,
              let session = captureSession,
              let delegate = recordingDelegate
        else {
            return
        }

        output.stopRecording()

        // Wait for the didFinishRecordingTo callback.
        await delegate.waitForCompletion()

        session.stopRunning()

        // Check for errors after completion.
        if let error = delegate.captureError {
            // Handle partial file recovery.
            if let url = currentOutputURL,
               FileManager.default.fileExists(atPath: url.path) {
                let partialURL = url.deletingPathExtension().appendingPathExtension("m4a.partial")
                try? FileManager.default.moveItem(at: url, to: partialURL)
            }
            throw RecorderError.recordingFailed(underlying: error)
        }
    }
    #else
    private func beginCapture(url: URL) async throws {
        throw RecorderError.permissionDenied("AVFoundation is not available on this platform.")
    }

    private func endCapture() async throws {}
    #endif

    // MARK: - Private: Helpers

    private nonisolated static func makeOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.timeZone = TimeZone.current
        let filename = "\(formatter.string(from: Date())).m4a"

        let documentsDir = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())

        return documentsDir.appending(path: filename)
    }

    private nonisolated static func ensureParentDirectory(_ url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
    }
}

#if canImport(AVFoundation)
// AI:
//   what: RecordingOutputDelegate bridges AVCaptureFileOutput callback to async/await
//   why:  stopRecording is async but completion is via delegate callback;
//         CheckedContinuation bridges this per Swift concurrency rule 14
//   ref:  specs/recording.md didFinishedRecordingTo callback

private final class RecordingOutputDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Never>?

    var captureError: Error?

    @MainActor
    func waitForCompletion() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.continuation = cont
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        captureError = error

        let cont = continuation
        continuation = nil

        cont?.resume()
    }
}
#endif
