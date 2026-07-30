#!/usr/bin/env swift
import Foundation
import AVFoundation
import Darwin

struct Options {
    var output = "recording.mov"
    var duration: Double?
    var camera: String?
    var microphone: String?
    var listDevices = false
    var preset = "high"
}

enum RecorderError: LocalizedError {
    case permissionDenied(String)
    case noDevice(String)
    case cannotAddInput(String)
    case cannotAddOutput
    case invalidDuration
    case invalidPreset(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let kind):
            return "\(kind) permission was denied. Enable it in System Settings > Privacy & Security."
        case .noDevice(let kind):
            return "No matching \(kind) device was found."
        case .cannotAddInput(let kind):
            return "The capture session could not add the \(kind) input."
        case .cannotAddOutput:
            return "The capture session could not add the movie output."
        case .invalidDuration:
            return "--duration must be a positive number of seconds."
        case .invalidPreset(let value):
            return "Unsupported preset '\(value)'. Use high, 720p, or 1080p."
        }
    }
}

func usage() {
    print("""
    Native macOS webcam recorder

    Usage:
      webcam-record [options]

    Options:
      -o, --output PATH          Output QuickTime movie (default: recording.mov)
      -d, --duration SECONDS     Stop automatically after this many seconds
          --camera TEXT          Camera name or unique-ID substring
          --microphone TEXT      Microphone name or unique-ID substring
          --preset VALUE         high, 720p, or 1080p (default: high)
          --list-devices         List available cameras and microphones
      -h, --help                 Show this help

    Examples:
      webcam-record -o demo.mov
      webcam-record -o demo.mov --duration 30
      webcam-record --list-devices
      webcam-record --camera "MacBook Pro Camera" --microphone "MacBook Pro Microphone"

    Press Ctrl+C to stop a recording cleanly.
    """)
}

func parseOptions() throws -> Options {
    var options = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    var index = 0

    while index < args.count {
        let arg = args[index]

        func requireValue() -> String {
            index += 1
            guard index < args.count else {
                fputs("Missing value after \(arg)\n", stderr)
                exit(2)
            }
            return args[index]
        }

        switch arg {
        case "-o", "--output":
            options.output = requireValue()
        case "-d", "--duration":
            let raw = requireValue()
            guard let value = Double(raw), value > 0 else {
                throw RecorderError.invalidDuration
            }
            options.duration = value
        case "--camera":
            options.camera = requireValue()
        case "--microphone":
            options.microphone = requireValue()
        case "--preset":
            options.preset = requireValue().lowercased()
        case "--list-devices":
            options.listDevices = true
        case "-h", "--help":
            usage()
            exit(0)
        default:
            fputs("Unknown option: \(arg)\n\n", stderr)
            usage()
            exit(2)
        }

        index += 1
    }

    return options
}

func devices(for mediaType: AVMediaType) -> [AVCaptureDevice] {
    AVCaptureDevice.devices(for: mediaType)
}

func printDevices() {
    print("Video devices:")
    let videos = devices(for: .video)
    if videos.isEmpty {
        print("  (none)")
    } else {
        for (index, device) in videos.enumerated() {
            print("  [\(index)] \(device.localizedName)")
            print("      id: \(device.uniqueID)")
        }
    }

    print("\nAudio devices:")
    let audios = devices(for: .audio)
    if audios.isEmpty {
        print("  (none)")
    } else {
        for (index, device) in audios.enumerated() {
            print("  [\(index)] \(device.localizedName)")
            print("      id: \(device.uniqueID)")
        }
    }
}

func selectDevice(mediaType: AVMediaType, query: String?) -> AVCaptureDevice? {
    let available = devices(for: mediaType)

    guard let query, !query.isEmpty else {
        return AVCaptureDevice.default(for: mediaType) ?? available.first
    }

    let needle = query.lowercased()

    if let exact = available.first(where: {
        $0.localizedName.lowercased() == needle || $0.uniqueID.lowercased() == needle
    }) {
        return exact
    }

    return available.first(where: {
        $0.localizedName.lowercased().contains(needle) ||
        $0.uniqueID.lowercased().contains(needle)
    })
}

func requestPermission(for mediaType: AVMediaType, label: String) throws {
    switch AVCaptureDevice.authorizationStatus(for: mediaType) {
    case .authorized:
        return
    case .denied, .restricted:
        throw RecorderError.permissionDenied(label)
    case .notDetermined:
        let semaphore = DispatchSemaphore(value: 0)
        var granted = false

        AVCaptureDevice.requestAccess(for: mediaType) { allowed in
            granted = allowed
            semaphore.signal()
        }

        semaphore.wait()

        if !granted {
            throw RecorderError.permissionDenied(label)
        }
    @unknown default:
        throw RecorderError.permissionDenied(label)
    }
}

final class Recorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private var signalSources: [DispatchSourceSignal] = []
    private var stopping = false
    private let outputURL: URL
    private let options: Options

    init(options: Options) {
        self.options = options
        self.outputURL = URL(
            fileURLWithPath: NSString(string: options.output).expandingTildeInPath
        ).standardizedFileURL
        super.init()
    }

    func configureAndStart() throws {
        try requestPermission(for: .video, label: "Camera")
        try requestPermission(for: .audio, label: "Microphone")

        guard let camera = selectDevice(mediaType: .video, query: options.camera) else {
            throw RecorderError.noDevice("camera")
        }

        guard let microphone = selectDevice(mediaType: .audio, query: options.microphone) else {
            throw RecorderError.noDevice("microphone")
        }

        session.beginConfiguration()

        switch options.preset {
        case "high":
            session.sessionPreset = .high
        case "720p":
            guard session.canSetSessionPreset(.hd1280x720) else {
                session.commitConfiguration()
                throw RecorderError.invalidPreset("720p (unsupported by this camera)")
            }
            session.sessionPreset = .hd1280x720
        case "1080p":
            guard session.canSetSessionPreset(.hd1920x1080) else {
                session.commitConfiguration()
                throw RecorderError.invalidPreset("1080p (unsupported by this camera)")
            }
            session.sessionPreset = .hd1920x1080
        default:
            session.commitConfiguration()
            throw RecorderError.invalidPreset(options.preset)
        }

        let cameraInput = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(cameraInput) else {
            session.commitConfiguration()
            throw RecorderError.cannotAddInput("camera")
        }
        session.addInput(cameraInput)

        let microphoneInput = try AVCaptureDeviceInput(device: microphone)
        guard session.canAddInput(microphoneInput) else {
            session.commitConfiguration()
            throw RecorderError.cannotAddInput("microphone")
        }
        session.addInput(microphoneInput)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw RecorderError.cannotAddOutput
        }
        session.addOutput(output)

        if let videoConnection = output.connection(with: .video),
           output.availableVideoCodecTypes.contains(.h264) {
            output.setOutputSettings(
                [AVVideoCodecKey: AVVideoCodecType.h264],
                for: videoConnection
            )
        }

        session.commitConfiguration()

        let directory = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        installSignalHandler()

        session.startRunning()
        output.startRecording(to: outputURL, recordingDelegate: self)

        print("Camera:      \(camera.localizedName)")
        print("Microphone:  \(microphone.localizedName)")
        print("Output:      \(outputURL.path)")
        if let duration = options.duration {
            print("Duration:    \(duration) seconds")
        } else {
            print("Stop:        Ctrl+C")
        }

        if let duration = options.duration {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                self?.stop()
            }
        }
    }

    private func installSignalHandler() {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        for sig in [SIGINT, SIGTERM] {
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.stop()
            }
            source.resume()
            signalSources.append(source)
        }
    }

    func stop() {
        guard !stopping else { return }
        stopping = true

        if output.isRecording {
            print("\nStopping and finalizing movie…")
            output.stopRecording()
        } else {
            session.stopRunning()
            exit(0)
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        print("Recording started.")
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        session.stopRunning()

        if let error {
            let nsError = error as NSError
            let completed = nsError.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false

            if !completed {
                fputs("Recording failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        print("Saved: \(outputFileURL.path)")
        exit(0)
    }
}

do {
    let options = try parseOptions()

    if options.listDevices {
        printDevices()
        exit(0)
    }

    let recorder = Recorder(options: options)
    try recorder.configureAndStart()
    RunLoop.main.run()
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
