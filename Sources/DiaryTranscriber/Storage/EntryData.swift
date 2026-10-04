import Foundation

// AI:
//   what: EntryData wraps the per-entry file contents (audio URL, transcript text)
//   why:  specs/storage.md DiaryStore.data(for:) returns this type to the view-model;
//         avoids leaking raw file handles or storage internals
//   ref:  specs/storage.md DiaryStore API

public struct EntryData: Sendable {
    public let audioURL: URL
    public let transcriptText: String
    public let metadata: DiaryEntry

    public init(audioURL: URL, transcriptText: String, metadata: DiaryEntry) {
        self.audioURL = audioURL
        self.transcriptText = transcriptText
        self.metadata = metadata
    }
}
