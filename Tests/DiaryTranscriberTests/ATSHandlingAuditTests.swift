import Foundation
import XCTest
@testable import DiaryTranscriberCore

// AI:
//   what: ATSHandlingAuditTests — verifies NSAppTransportSecurity exception scope
//         and the Whisper client's network-error mapping (PRD #40)
//   why:  PRD 40 (ATS Handling Audit) requires that ATS exceptions be scoped to
//         api.openai.com only with NSAllowsArbitraryLoads=false, and that TLS /
//         network-unavailable failures surface as TranscriptionError.networkUnavailable
//         with a '"Network unavailable: transcription failed"' description so the
//         user sees a clear error banner instead of a silent hang or restated
//         empty error.
//         - testATS_isScopedToOpenAIDomain parses Resources/Info.plist and asserts
//           the exception structure programmatically so a future edit that widens
//           ATS scope is caught by CI rather than by review.
//         - testNetworkUnavailable_errorDescription pins the localized string
//           required by the PRD.
//         - testClassifyURLError_* drives the WhisperClient test seam with each
//           URLError.Code that must map to networkUnavailable (transport + TLS)
//           and with a code that must pass through unchanged, so the mapping
//           table stays honest against the PRD's acceptance criteria.
//         - testErrorBanner_surfacedWhenTranscriptionFails pins the banner pathway
//           from finishRecording(entry, transcript, transcriptionFailureMessage).
//   ref:  PRD 40-ats-handling-audit
final class ATSHandlingAuditTests: XCTestCase {

    // MARK: - Info.plist ATS scope

    /// Parses Resources/Info.plist and asserts that:
    ///   - NSAllowsArbitraryLoads is false (both at top-level and inside NSAppTransportSecurity)
    ///   - NSExceptionDomains is present and contains ONLY api.openai.com
    ///   - the api.openai.com exception requires forward secrecy and pins TLSv1.2
    ///
    /// This is a structural audit; it fails the moment a future change widens ATS,
    /// adds a second exception domain, or removes the forward-secrecy/TLS pin.
    func testATS_isScopedToOpenAIDomain() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent("Info.plist")

        let data = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        let root = try XCTUnwrap(plist as? [String: Any])

        // Top-level NSAllowsArbitraryLoads must be absent or false (never true).
        if let topArbitrary = root["NSAllowsArbitraryLoads"] as? Bool {
            XCTAssertFalse(
                topArbitrary,
                "Top-level NSAllowsArbitraryLoads must be false"
            )
        }

        let ats = try XCTUnwrap(
            root["NSAppTransportSecurity"] as? [String: Any],
            "NSAppTransportSecurity block must be present in Info.plist"
        )

        // Inside ATS: NSAllowsArbitraryLoads must be explicitly false.
        let atsArbitrary = try XCTUnwrap(
            ats["NSAllowsArbitraryLoads"] as? Bool,
            "NSAppTransportSecurity.NSAllowsArbitraryLoads must be set"
        )
        XCTAssertFalse(
            atsArbitrary,
            "NSAppTransportSecurity.NSAllowsArbitraryLoads must be false"
        )

        let domains = try XCTUnwrap(
            ats["NSExceptionDomains"] as? [String: Any],
            "NSExceptionDomains must be present under NSAppTransportSecurity"
        )

        // Exactly one exception domain: api.openai.com.
        XCTAssertEqual(
            Set(domains.keys),
            Set(["api.openai.com"]),
            "ATS exception domains must be scoped to api.openai.com only — found: \(domains.keys)"
        )

        let openAI = try XCTUnwrap(
            domains["api.openai.com"] as? [String: Any],
            "api.openai.com exception must be a dict"
        )

        // The exception must pin forward secrecy and a minimum of TLSv1.2.
        let requiresFS = try XCTUnwrap(
            openAI["NSExceptionRequiresForwardSecrecy"] as? Bool,
            "api.openai.com exception must set NSExceptionRequiresForwardSecrecy"
        )
        XCTAssertTrue(requiresFS, "Forward secrecy must be required for api.openai.com")

        let minTLS = try XCTUnwrap(
            openAI["NSExceptionMinimumTLSVersion"] as? String,
            "api.openai.com exception must set NSExceptionMinimumTLSVersion"
        )
        XCTAssertEqual(
            minTLS,
            "TLSv1.2",
            "Minimum TLS version for api.openai.com must be pinned to TLSv1.2"
        )
    }

    // MARK: - networkUnavailable error description

    func testNetworkUnavailable_errorDescription_matchesPRD() {
        // PRD #40 requirement 2: errorDescription reads "Network unavailable: transcription failed".
        let desc = TranscriptionError.networkUnavailable.errorDescription
        XCTAssertEqual(
            desc,
            "Network unavailable: transcription failed",
            "networkUnavailable.errorDescription must match the PRD-40 wording"
        )
    }

    // MARK: - WhisperClient classifyURLError (test seam)

    func testClassifyURLError_networkTransportFailures_mapToNetworkUnavailable() {
        // AI: These URLError.Codes represent "the request never reached OpenAI"
        //     (link down, no route, DNS failure). They must all surface as
        //     networkUnavailable so the user sees the PRD-40 banner, not a bare
        //     URLError restated as a generic "Transcription failed: …".
        let transportCodes: [URLError.Code] = [
            .notConnectedToInternet,
            .cannotFindHost,
            .cannotConnectToHost,
            .networkConnectionLost,
            .dnsLookupFailed,
            .dataNotAllowed,
        ]

        for code in transportCodes {
            let error = URLError(code)
            let classified = WhisperClient.classifyURLErrorForTest(error)
            if case .networkUnavailable = classified as? TranscriptionError {
                // expected
            } else {
                XCTFail("URLError \(code) should map to networkUnavailable, got \(classified)")
            }
        }
    }

    // MARK: - WhisperClient oath classifyURLError

    func testClassifyURLError_tlsFailures_mapToNetworkUnavailable() {
        // AI: TLS handshake / certificate validation failures (the path taken when
        //     OpenAI rotates certs or a TLS config the app's pinned connection
        //     does not accept). PRD calls these "TLS-rejected" connections and
        //     requires they surface with errorDescription.
        let tlsCodes: [URLError.Code] = [
            .secureConnectionFailed,
            .serverCertificateUntrusted,
            .serverCertificateHasBadDate,
            .serverCertificateNotYetValid,
        ]

        for code in tlsCodes {
            let error = URLError(code)
            let classified = WhisperClient.classifyURLErrorForTest(error)
            if case .networkUnavailable = classified as? TranscriptionError {
                // expected
            } else {
                XCTFail("URLError \(code) should map to networkUnavailable (TLS rejection), got \(classified)")
            }
        }
    }

    func testClassifyURLError_otherURLErrors_passThroughUnchanged() {
        // AI: URLErrors that are NOT network/TLS failures must pass through so the
        //     TranscriptionService's catch-all can still format them generically.
        //     timedOut, for example, must NOT be remapped to networkUnavailable —
        //     the TranscriptionService's outer timeout wrapper emits whisperTimeout.
        let timeoutError = URLError(.timedOut)
        let classified = WhisperClient.classifyURLErrorForTest(timeoutError)
        if case .networkUnavailable = classified as? TranscriptionError {
            XCTFail("URLError.timedOut must not be remapped to networkUnavailable")
        }

        // A non-URLError must pass through untouched.
        let otherError = NSError(domain: "TestDomain", code: 42, userInfo: nil)
        let untouched = WhisperClient.classifyURLErrorForTest(otherError as Error)
        XCTAssertTrue(
            (untouched as NSError).isEqual(otherError),
            "Non-URLError errors must pass through classifyURLError unchanged"
        )
    }

    // MARK: - ErrorBanner pathway via finishRecording

    @MainActor
    func testFinishRecording_transcriptionFailureMessage_setsErrorBanner() async throws {
        // AI: PRD #40 — when finishRecording is called with a transcription failure
        //     message (e.g. "Network unavailable: transcription failed"), the entry
        //     is still persisted (audio is never lost) but errorBanner is set so the
        //     user sees the reason via the existing PRD-25 banner pathway.
        let sourceDir = FileManager.default.temporaryDirectory
            .appending(path: "ats-finish-src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDir) }

        let audioFile = sourceDir.appending(path: "net-fail.m4a")
        try "fake audio data".write(to: audioFile, atomically: true, encoding: .utf8)

        let storeDir = FileManager.default.temporaryDirectory
            .appending(path: "ats-finish-store-\(UUID().uuidString)")
        let store = DiaryStore(folder: storeDir)
        defer { try? FileManager.default.removeItem(at: storeDir) }

        let vm = ListViewModel(store: store)
        await vm.refresh()

        let entry = DiaryEntry(
            startedAt: Date(),
            durationSeconds: 5,
            audioPath: audioFile.path,
            transcriptPath: audioFile.deletingPathExtension().appendingPathExtension("md").path,
            source: .none
        )

        // Simulate a network-unavailable transcription failure surfaced from the
        // post-recording pipeline. The entry SHOULD still be persisted.
        await vm.finishRecording(
            entry: entry,
            transcript: nil,
            transcriptionFailureMessage: "Network unavailable: transcription failed"
        )

        // Entry persisted (audio not lost).
        XCTAssertEqual(vm.entries.count, 1, "Entry should be persisted even when transcription failed")

        // Banner surfaces the network failure.
        XCTAssertNotNil(vm.errorBanner, "errorBanner should be set when transcription fails")
        XCTAssertEqual(
            vm.errorBanner,
            "Network unavailable: transcription failed",
            "errorBanner should echo the transcription failure message"
        )
    }

    @MainActor
    func testFinishRecording_noFailureMessage_clearsErrorBanner() async throws {
        // AI: PRD #40 — the banner must NOT linger when a subsequent successful
        //     recording completes with no failure message. This mirrors PRD #25's
        //     "success: clear any prior error banner" rule, so a user who retries
        //     recording after a network failure sees the banner clear from screen.
        let sourceDir = FileManager.default.temporaryDirectory
            .appending(path: "ats-clear-src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDir) }

        let audioFile = sourceDir.appending(path: "ok-recording.m4a")
        try "fake audio data".write(to: audioFile, atomically: true, encoding: .utf8)

        let storeDir = FileManager.default.temporaryDirectory
            .appending(path: "ats-clear-store-\(UUID().uuidString)")
        let store = DiaryStore(folder: storeDir)
        defer { try? FileManager.default.removeItem(at: storeDir) }

        let vm = ListViewModel(store: store)
        await vm.refresh()

        // Seed a prior banner.
        vm.errorBanner = "stale prior error"

        let entry = DiaryEntry(
            startedAt: Date(),
            durationSeconds: 5,
            audioPath: audioFile.path,
            transcriptPath: audioFile.deletingPathExtension().appendingPathExtension("md").path,
            source: .none
        )

        await vm.finishRecording(
            entry: entry,
            transcript: nil,
            transcriptionFailureMessage: nil
        )

        XCTAssertNil(
            vm.errorBanner,
            "A successful finish with no failure message must clear errorBanner"
        )
    }
}
