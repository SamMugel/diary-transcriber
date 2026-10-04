import Foundation

// AI:
//   what: WhisperClient actor transcribes audio via the OpenAI Whisper API
//   why:  D-0004 hybrid transcription: Whisper is the fallback engine when on-device
//         Speech fails or produces low-quality output; requires an API key and network
//   ref:  specs/transcription.md WhisperClient API, D-0004

public actor WhisperClient {

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
        return try await URLSession.shared.data(for: request)
    }

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
