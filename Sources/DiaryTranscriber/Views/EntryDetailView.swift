import SwiftUI

// AI:
//   what: EntryDetailView — full transcript view with audio playback controls
//   why:  specs/ui.md: scrollable TextEditor transcript, play/pause + scrubber + timecode,
//         Re-transcribe button when source=.none, save on blur via DiaryStore.update()
//   ref:  specs/ui.md EntryDetailView, D-0005, D-0008

public struct EntryDetailView: View {

    @State private var viewModel: EntryDetailViewModel

    public init(viewModel: EntryDetailViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            playbackControls
            Divider()
            transcriptEditor
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await viewModel.loadData()
            await viewModel.loadAudio()
        }
        .onDisappear {
            Task { await viewModel.saveIfChanged() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.entry.startedAt, format: .dateTime)
                    .font(.headline)
                Text(sourceLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.showRetranscribe {
                Button("Re-transcribe") {
                    // Trigger re-transcription — handled by parent or future wiring.
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var sourceLabel: String {
        switch viewModel.entry.source {
        case .speech: "Transcribed with on-device Speech"
        case .whisper: "Transcribed with Whisper API"
        case .none: "Not yet transcribed"
        }
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.togglePlayback()
            } label: {
                Image(systemName: viewModel.audioPlayer.isPlaying
                    ? "pause.circle.fill"
                    : "play.circle.fill")
                    .font(.title)
            }
            .buttonStyle(.borderless)
            .help(viewModel.audioPlayer.isPlaying ? "Pause" : "Play")

            Text(viewModel.audioPlayer.timecode)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { viewModel.audioPlayer.progress },
                    set: { newValue in
                        viewModel.seek(to: newValue)
                    }
                ),
                in: 0...1
            )

            Text(formattedDuration)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var formattedDuration: String {
        let total = Int(viewModel.audioPlayer.duration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Transcript Editor

    private var transcriptEditor: some View {
        TextEditor(text: Binding(
            get: { viewModel.transcriptText },
            set: { newValue in
                viewModel.updateTranscript(newValue)
            }
        ))
        .font(.body)
        .padding(.horizontal, 12)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            // Auto-save on blur: handled by onDisappear above.
        }
    }
}

#if canImport(AppKit)
import AppKit
#endif

#Preview {
    EntryDetailView(
        viewModel: EntryDetailViewModel(
            entry: DiaryEntry(
                startedAt: Date(),
                durationSeconds: 120,
                audioPath: "test.m4a",
                transcriptPath: "test.md",
                source: .speech
            )
        )
    )
}
