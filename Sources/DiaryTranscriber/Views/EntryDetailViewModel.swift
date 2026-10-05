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

    public let audioPlayer: AudioPlayer

    private let store: DiaryStore?
    // AI: PRD #28 — shared TranscriptionService injected from AppEnvironment. Optional + nil-default
    //     so existing tests that construct `EntryDetailViewModel(entry:)` keep compiling. #28 only wires
    //     it here; #26/#18 will consume it for re-transcription.
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
