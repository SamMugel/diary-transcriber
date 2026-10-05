import Foundation

// AI:
//   what: WhisperClient actor transcribes audio via the OpenAI Whisper API
//   why:  D-0004 hybrid transcription: Whisper is the fallback engine when on-device
//         Speech fails or produces low-quality output; requires an API key and network
//   ref:  specs/transcription.md WhisperClient API, D-0004

public actor WhisperClient: WhisperClientProtocol {

    private let apiKey: String
    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    private let timeout: TimeInterval = 120
    private let model = "whisper-1"

    // MARK: - Lifecycle

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Public API

    public func transcribe(at audioURL: URL) async throws -> Transcript {
        guard !apiKey.isEmpty else {
            throw TranscriptionError.whisperError(status: 401)
        }

        let request = try buildRequest(audioURL: audioURL)
        let (data, response) = try await sendRequest(request)

        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 0

        guard (200..<300).contains(statusCode) else {
            // Never include API key or audio contents in the error.
            throw TranscriptionError.whisperError(status: statusCode)
        }

        return try parseResponse(data: data)
    }

    // MARK: - Private: Request building

    private nonisolated func buildRequest(audioURL: URL) throws -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        let body = try buildMultipartBody(
            audioURL: audioURL,
            boundary: boundary
        )
        request.httpBody = body

        return request
    }

    private nonisolated func buildMultipartBody(
        audioURL: URL,
        boundary: String
    ) throws -> Data {
        var body = Data()

        // model field
        body.append(Self.field(boundary: boundary, name: "model", value: model))

        // audio file
        let audioData = try Data(contentsOf: audioURL)
        let filename = audioURL.lastPathComponent
        let mimeType = mimeTypeFor(audioURL)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return body
    }

    // MARK: - Private: Network

    private nonisolated func sendRequest(
        _ request: URLRequest
    ) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            // AI: PRD #40 — map TLS-rejected / network-unavailable URLSession errors to
            //     TranscriptionError.networkUnavailable so the failure surfaces to the user
            //     via the error-banner pathway instead of propagating a bare URLError that
            //     the TranscriptionService would restate as "Transcription failed: …".
            //     A 120s server-side timeout (URLSession's timeoutInterval) is left to the
            //     TranscriptionService's outer timeout wrapper, which already emits
            //     whisperTimeout — so timedOut is NOT remapped here.
            throw Self.classifyURLError(error)
        }
    }

    // AI:
    //   what: classifyURLError — decides whether a URLSession-thrown error is a
    //         network/TLS failure that should surface as networkUnavailable
    //   why:  PRD #40 — TLS handshake failures (secureConnectionFailed, a TLS-
    //         rejected CA or cipher mismatch) and link-level failures (no route
    //         to host, cannot connect, not connected to internet, DNS lookup
    //         failure) all represent "the request never reached OpenAI"; they
    //         must surface the typed networkUnavailable case so the user sees
    //         "Network unavailable: transcription failed" in the error banner.
    //         Non-transport URLErrors (e.g. badURL) and non-network exceptions
    //         pass through unchanged so the caller's catch-all in
    //         TranscriptionService can still format them generically.
    //   ref:  PRD 40-ats-handling-audit, acceptance criteria 1 & 2
    private nonisolated static func classifyURLError(_ error: Error) -> Error {
        guard let urlError = error as? URLError else {
            return error
        }

        switch urlError.code {
        // Physical transport failures — the host could not be reached.
        case .notConnectedToInternet,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .dataNotAllowed:
            return TranscriptionError.networkUnavailable

        // TLS handshake / certificate rejection — distinct from an app-side ATS
        // load (ATS enforcement happens before the URLSession error is even
        // thrown), but this is the path taken when OpenAI rotates certs or
        // rotates a TLS configuration that the App's pinned connection does
        // not yet accept. Treat as a network failure per the PRD's "TLS-
        // rejected" criterion. These are the cert-validation failures exposed
        // by Foundation's URLError.Code; other revocation/expiry conditions
        // surface as secureConnectionFailed on this platform.
        case .secureConnectionFailed,
             .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateNotYetValid:
            return TranscriptionError.networkUnavailable

        default:
            return error
        }
    }

    // AI: PRD #40 — test-only pass-through for the private classifyURLError classifier.
    //     Lets ATSHandlingAuditTests assert the URLError → TranscriptionError mapping
    //     without hitting the network (WhisperClient's endpoint is hardcoded to
    //     api.openai.com, so a live request would be non-deterministic in CI).
    //     Mirrors the `#if DEBUG internal` seam convention used by
    //     RecordingViewModel.startTimerForTest(). Reads exactly the same code path as
    //     the production sendRequest catch.
    //   ref: PRD 40-ats-handling-audit
    #if DEBUG
    internal nonisolated static func classifyURLErrorForTest(_ error: Error) -> Error {
        classifyURLError(error)
    }
    #endif

    // MARK: - Private: Response parsing

    private func parseResponse(data: Data) throws -> Transcript {
        let decoder = JSONDecoder()
        let result = try decoder.decode(
            WhisperResponse.self,
            from: data
        )

        return Transcript(
            text: result.text,
            confidence: nil,
            source: .whisper,
            isFinal: true
        )
    }

    // MARK: - Private: Helpers

    private nonisolated func mimeTypeFor(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m4a":
            "audio/mp4"
        case "mp3":
            "audio/mpeg"
        case "wav":
            "audio/wav"
        case "ogg":
            "audio/vorbis"
        default:
            "application/octet-stream"
        }
    }

    private nonisolated static func field(
        boundary: String,
        name: String,
        value: String
    ) -> Data {
        var data = Data()
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append(
            "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
                .data(using: .utf8)!)
        data.append("\(value)\r\n".data(using: .utf8)!)
        return data
    }
}

// AI:
//   what: WhisperResponse — JSON schema for POST /v1/audio/transcriptions response
//   why:  OpenAI returns {"text": "..."} on success; decode defensively
//   ref:  specs/transcription.md API key, D-0004

private struct WhisperResponse: Decodable {
    let text: String
}
