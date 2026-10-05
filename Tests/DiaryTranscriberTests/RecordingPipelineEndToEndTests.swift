import XCTest
@testable import DiaryTranscriberCore

// AI:
//   what: StubAudioRecorder — actor conforming to AudioRecorderProtocol for E2E pipeline tests
//   why:  PRD #35 — the end-to-end pipeline test must drive RecordingViewModel.start→stop
//         WITHOUT a real microphone. This stub returns a RecordingHandle pointing at a
//         pre-written fixture .m4a (supplied by the test) and surfaces the same URL from
//         stop() so that ListViewModel.finishRecording can move a real file into the store.
//         Conforms to the Sendable protocol so a @MainActor RecordingViewModel can hold it
//         across actor boundaries under Swift 6 strict concurrency.
//   ref:  PRD 35-end-to-end-record-pipeline-tests, AudioRecorderProtocol
actor StubAudioRecorder: AudioRecorderProtocol {
    /// Fixed fixture URL the stub hands back from both start() and stop().
    private let fixtureURL: URL

    init(fixtureURL: URL) {
        self.fixtureURL = fixtureURL
    }

    func start() async throws -> RecordingHandle {
        // Return a genuine RecordingHandle so the view-model's timer + isRecording
        // logic operate on the real type (no sentinel/placeholder values).
        return RecordingHandle(startedAt: Date(), outputURL: fixtureURL)
    }

    func stop() async throws -> URL {
        // Hand back the fixture URL exactly as AudioRecorder.stop() would the captured .m4a.
        fixtureURL
    }

    func currentElapsedTime() async -> Double {
        // Deterministic small elapsed value; never consulted by the pipeline under test.
        0.05
    }
}

// AI:
//   what: StubTranscriptionService — actor conforming to TranscriptionServiceProtocol for E2E tests
//   why:  PRD #35 — the pipeline test must drive RecordingViewModel.stop() through the
//         TranscriptionService stream WITHOUT a real SFSpeechRecognizer or Whisper network
//         call. This stub yields a single deterministic TranscriptUpdate.final whose
//         Transcript carries a fixed text + source, then finishes the AsyncStream so the
//         for-await loop in stop() terminates promptly. The service never touches the disk
//         or network; the audioURL is recorded only so the test can assert it was forwarded.
//   ref:  PRD 35-end-to-end-record-pipeline-tests, TranscriptionServiceProtocol
actor StubTranscriptionService: TranscriptionServiceProtocol {
    /// The fixed Transcript the stub yields in every transcribe() stream.
    private let transcript: Transcript

    init(transcript: Transcript) {
        self.transcript = transcript
    }

    func transcribe(at audioURL: URL) async -> AsyncStream<TranscriptUpdate> {
        AsyncStream { continuation in
            continuation.yield(.final(transcript))
            continuation.finish()
        }
    }

    func replaceWhisperClient(_ client: WhisperClientProtocol?) async {
        // No-op: the stub has no Whisper client and never will.
    }

    func hasWhisperClient() async -> Bool {
        false
    }
}

// AI:
//   what: RecordingPipelineEndToEndTests — end-to-end pipeline integration test
//   why:  PRD #35 — verifies the full start→stop→finalize→persist pipeline with stubbed
//         deps (no mic, no network). Drives RecordingViewModel through start()→stop(),
//         asserts completedEntry/completedTranscript are populated, then mirrors the
//         RecordingView.onCompleted closure by invoking ListViewModel.finishRecording
//         and asserts the DiaryEntry lands in the store. The test runs in <2s, is
//         isolated to a UUID'd NSTemporaryDirectory, and cleans up in tearDown.
//   ref:  PRD 35-end-to-end-record-pipeline-tests
final class RecordingPipelineEndToEndTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "PipelineE2E-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // AI: PRD #35 — the canonical one-test acceptance criterion: drives
    //     start→stop→finalize→persist with stub deps and asserts a persisted
    //     DiaryEntry lands in the store, all under Swift 6 strict concurrency
    //     on the @MainActor ViewModel path.
    @MainActor
    func testRecordPipeline_start_stop_finalize_persist_endToEnd() async throws {
        // --- Arrange: fixture .m4a in a source directory SEPARATE from the store ---

        // In the real flow AudioRecorder writes to ~/Documents (source) and
        // finishRecording moves the file into the store folder. If the fixture is
        // placed directly in the store dir, `try? removeItem(at: destURL)` in
        // finishRecording deletes it before the move (source == dest). We mirror
        // the real two-directory topology with a dedicated source subdir.
        let sourceDir = tempDir.appending(path: "fixture-src")
        try FileManager.default.createDirectory(
            at: sourceDir,
            withIntermediateDirectories: true
        )
        let fixtureURL = sourceDir.appending(path: "fixture-recording.m4a")
        try "fixture audio bytes".write(
            to: fixtureURL,
            atomically: true,
            encoding: .utf8
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixtureURL.path),
            "Precondition: fixture .m4a must exist on disk before stop()"
        )

        // Deterministic Transcript the stub service yields (PRD: "deterministic TranscriptUpdate.final").
        let expectedTranscript = Transcript(
            text: "End-to-end pipeline test transcript.",
            confidence: 0.97,
            source: .whisper,
            isFinal: true
        )

        let stubRecorder = StubAudioRecorder(fixtureURL: fixtureURL)
        let stubService = StubTranscriptionService(transcript: expectedTranscript)

        // --- Act (phase 1): start → brief wait → stop on the RecordingViewModel ---

        let recordingVM = RecordingViewModel(
            recorder: stubRecorder,
            speechTranscriber: nil,        // no live speech stream in CI
            transcriptionService: stubService
        )

        await recordingVM.start()
        // Brief wait so the timer Task ticks at least once (mirrors a real recording).
        // Kept well under the 2-second acceptance budget.
        try? await Task.sleep(for: .milliseconds(50))

        // stop() runs the transcription pipeline (stub yields .final) and populates
        // completedEntry / completedTranscript.
        await recordingVM.stop()

        // --- Assert (phase 1): RecordingViewModel produced a completed entry + transcript ---

        XCTAssertNotNil(
            recordingVM.completedEntry,
            "stop() must populate completedEntry when the pipeline yields a final transcript"
        )
        XCTAssertNotNil(
            recordingVM.completedTranscript,
            "stop() must populate completedTranscript when the pipeline yields a .final update"
        )
        XCTAssertEqual(
            recordingVM.completedTranscript?.text,
            expectedTranscript.text,
            "completedTranscript must match the stub service's deterministic Transcript.text"
        )
        XCTAssertEqual(
            recordingVM.completedTranscript?.source,
            .whisper,
            "completedTranscript must carry the stub service's deterministic source"
        )
        XCTAssertFalse(
            recordingVM.isRecording,
            "isRecording must be false after stop() returns"
        )
        XCTAssertFalse(
            recordingVM.isFinalizing,
            "isFinalizing must be false after stop() returns"
        )

        // --- Act (phase 2): mirror RecordingView.onCompleted via ListViewModel.finishRecording ---

        let store = DiaryStore(folder: tempDir)
        let listVM = ListViewModel(store: store)
        await listVM.refresh()
        XCTAssertEqual(listVM.entries.count, 0, "Store should be empty before finishRecording")

        // On a real RecordingView this is what the onCompleted closure performs.
        await listVM.finishRecording(
            entry: recordingVM.completedEntry!,
            transcript: recordingVM.completedTranscript
        )

        // --- Assert (phase 2): the DiaryEntry landed in the store and the VM reset ---

        XCTAssertFalse(
            listVM.isRecording,
            "isRecording must be false after finishRecording (mirrors onCompleted reset to the list VM)"
        )
        XCTAssertFalse(
            listVM.showRecordingSheet,
            "showRecordingSheet must be false after finishRecording"
        )
        XCTAssertNil(
            listVM.errorBanner,
            "finishRecording must not surface an error on the happy path"
        )

        let persistedEntries = try await store.entries()
        XCTAssertEqual(
            persistedEntries.count,
            1,
            "Exactly one DiaryEntry should be persisted after finishRecording"
        )

        guard let persisted = persistedEntries.first else {
            XCTFail("Expected a persisted DiaryEntry but got none")
            return
        }

        XCTAssertEqual(
            persisted.id,
            recordingVM.completedEntry!.id,
            "Persisted entry id must match the completedEntry id from the recording VM"
        )
        XCTAssertEqual(
            persisted.source,
            .whisper,
            "Persisted entry source must reflect the transcript produced by the stub service"
        )
        XCTAssertEqual(
            persisted.durationSeconds,
            recordingVM.completedEntry!.durationSeconds,
            "Persisted durationSeconds must match the completedEntry's duration"
        )

        // The audio file must have been moved into the store folder (not left at the
        // fixture location), proving the full finalize→persist path moved real bytes.
        let movedAudio = tempDir.appending(path: "fixture-recording.m4a")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: movedAudio.path),
            "Fixture .m4a should have been moved into the store folder by finishRecording"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixtureURL.path),
            "Original fixture .m4a should no longer exist at the source path (moved, not copied)"
        )

        // The timeline reflects the persisted entry immediately after finishRecording's refresh.
        XCTAssertTrue(
            listVM.entries.contains(where: { $0.id == persisted.id }),
            "ListViewModel.entries must contain the persisted DiaryEntry"
        )
    }
}
