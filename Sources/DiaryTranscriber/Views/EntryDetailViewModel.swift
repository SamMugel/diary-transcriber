import SwiftUI

// AI:
//   what: EntryDetailViewModel — @MainActor observable backing EntryDetailView
//   why:  specs/ui.md: entry, audioPlayer, transcriptText state; loads transcript
//         from DiaryStore and saves edits on blur
//   ref:  specs/ui.md EntryDetailView, D-0005, D-0008

@MainActor
@Observable
public final class EntryDetailViewModel {

    public var entry: DiaryEntry
    public var transcriptText: String = ""
    public var hasUnsavedChanges = false

    // AI: PRD #26 — re-transcription state surfaced to EntryDetailView.
    //     `isRetranscribing` drives a ProgressView + disabled button while the
    //     service's AsyncStream is iterating; `retranscribeError` is the typed
    //     inline failure state (kept distinct from `transcriptText` so the user
    //     can read the failure reason and retry).
    //     See PRD/26-retranscribe-button.json.
    public var isRetranscribing = false
    public var retranscribeError: String = ""

    public let audioPlayer: AudioPlayer

    private let store: DiaryStore?
    // AI: PRD #28 — shared TranscriptionService injected from AppEnvironment. Optional + nil-default
    //     so existing tests that construct `EntryDetailViewModel(entry:)` keep compiling. #28 wired
    //     the field; #18 left it consumed by RecordingViewModel; #26 now consumes it here for
    //     re-transcription via `retranscribe()`. See PRD 26-retranscribe-button.json.
    private let transcriptionService: TranscriptionService?

    public init(
        entry: DiaryEntry,
        store: DiaryStore? = nil,
        audioPlayer: AudioPlayer = AudioPlayer(),
        transcriptionService: TranscriptionService? = nil
    ) {
        self.entry = entry
        self.store = store
        self.audioPlayer = audioPlayer
        self.transcriptionService = transcriptionService
    }

    public var showRetranscribe: Bool {
        entry.source == .none
    }

    public func loadData() async {
        guard let store else { return }
        do {
            let data = try await store.data(for: entry)
            transcriptText = data.transcriptText
        } catch {
            transcriptText = ""
        }
    }

    public func loadAudio() async {
        guard let store else { return }
        let url = await store.url(for: entry)
        try? audioPlayer.load(from: url)
    }

    public func updateTranscript(_ text: String) {
        transcriptText = text
        hasUnsavedChanges = true
    }

    // AI:
    //   what: retranscribe() — drives the TranscriptionService stream for a .none entry and
    //         persists the final transcript onto disk.
    //   why:  PRD #26 — the Re-transcribe button (visible only when entry.source == .none)
    //         must re-run the hybrid Speech/Whisper pipeline and live-update the transcript
    //         editor. We iterate the `AsyncStream<TranscriptUpdate>` returned by the service:
    //           - `.partial(String)` updates `transcriptText` live so the user sees progress;
    //           - `.final(Transcript)` persists the finalized text through `store.setTranscript`
    //             (the manifest row already exists — the entry was appended during recording),
    //             upgrades `entry.source` to the transcript's source, and clears the unsaved
    //             flag (the .md file is now the source of truth);
    //           - `.failed(String)` sets `retranscribeError` so the view can surface it inline
    //             and the button can be re-enabled for retry.
    //         `isRetranscribing` toggles around the whole iteration so the UI can show a
    //         ProgressView and disable the button. It's reset in a defer so every exit path
    //         (success, failure, or thrown) restores it. A missing service or store is a
    //         silent no-op (mirrors the nil-default guard pattern in `loadData`/`saveIfChanged`).
    //   ref:  PRD 26-retranscribe-button.json, PRD 18 (setTranscript lifecycle)
    public func retranscribe() async {
        guard let service = transcriptionService else { return }
        guard let store else { return }
        guard entry.source == .none else { return }

        isRetranscribing = true
        retranscribeError = ""
        defer { isRetranscribing = false }

        let audioURL = await store.url(for: entry)
        let stream = await service.transcribe(at: audioURL)

        for await update in stream {
            switch update {
            case .partial(let text):
                transcriptText = text
            case .final(let transcript):
                do {
                    try await store.setTranscript(
                        for: entry.id,
                        source: transcript.source,
                        text: transcript.text
                    )
                    entry.source = transcript.source
                    transcriptText = transcript.text
                    hasUnsavedChanges = false
                } catch {
                    retranscribeError = error.localizedDescription
                }
            case .failed(let message):
                retranscribeError = message
            }
        }
    }

    public func saveIfChanged() async {
        guard hasUnsavedChanges, let store else { return }
        do {
            // AI: PRD #18 — route blur-save through `store.setTranscript` rather
            //     than `store.update` so the edited transcript text is persisted
            //     into the entry's `.md` (closing ISSUE-015's gap where inline
            //     edits only updated the manifest and never reached disk).
            //     The new source is kept if the entry has one, else `.none`.
            //     ref: PRD 18, ISSUE-015
            try await store.setTranscript(
                for: entry.id,
                source: entry.source,
                text: transcriptText
            )
            // Persist other metadata changes (e.g. duration) via the existing path.
            try await store.update(entry: entry)
            hasUnsavedChanges = false
        } catch {
            // Silently fail; could surface to UI later.
        }
    }

    public func togglePlayback() {
        audioPlayer.togglePlayPause()
    }

    public func seek(to progress: Double) {
        audioPlayer.scrub(to: progress)
    }
}
