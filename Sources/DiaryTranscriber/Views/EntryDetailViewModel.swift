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

    public init(
        entry: DiaryEntry,
        store: DiaryStore? = nil,
        audioPlayer: AudioPlayer = AudioPlayer()
    ) {
        self.entry = entry
        self.store = store
        self.audioPlayer = audioPlayer
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
