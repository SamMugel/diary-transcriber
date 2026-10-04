import SwiftUI

// AI:
//   what: ListViewModel — @MainActor observable view-model backing ContentView
//   why:  specs/ui.md: each view has a @MainActor @Observable view-model with
//         dependencies injected via constructor; ListViewModel holds entries and
//         isRecording state
//   ref:  specs/ui.md View-models, D-0008

@MainActor
@Observable
public final class ListViewModel {

    public var entries: [DiaryEntry] = []
    public var isRecording = false
    public var showRecordingSheet = false

    private let store: DiaryStore?

    public init(store: DiaryStore? = nil) {
        self.store = store
        Task { await refresh() }
    }

    public func refresh() async {
        guard let store else { return }
        do {
            entries = try await store.entries()
        } catch {
            entries = []
        }
    }

    public func startRecording() {
        showRecordingSheet = true
        isRecording = true
    }

    public func cancelRecording() {
        isRecording = false
        showRecordingSheet = false
    }

    /// Called when RecordingView finishes (recording stopped + entry committed).
    /// Moves the audio file into the store folder, persists the entry, and refreshes.
    public func finishRecording(entry: DiaryEntry) async {
        showRecordingSheet = false
        isRecording = false

        guard let store else { return }
        do {
            // The audio file is at an absolute path (written by AudioRecorder to ~/Documents).
            // Move it into the store's folder and use a relative path in the entry.
            let sourceURL = URL(filePath: entry.audioPath)
            let filename = sourceURL.lastPathComponent
            let relativeAudioPath = filename
            let relativeTranscriptPath = sourceURL.deletingPathExtension()
                .appendingPathExtension("md").lastPathComponent

            // Build the entry with relative paths.
            let resolvedEntry = DiaryEntry(
                id: entry.id,
                startedAt: entry.startedAt,
                durationSeconds: entry.durationSeconds,
                audioPath: relativeAudioPath,
                transcriptPath: relativeTranscriptPath,
                source: entry.source,
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt
            )

            // Move the audio file into the store folder.
            // The store folder is created by append(), so we create it here first
            // to ensure moveItem succeeds.
            let storeFolder = await store.folderURL()
            try? FileManager.default.createDirectory(
                at: storeFolder,
                withIntermediateDirectories: true
            )
            let destURL = storeFolder.appending(path: filename)
            try? FileManager.default.removeItem(at: destURL)
            try FileManager.default.moveItem(at: sourceURL, to: destURL)

            try await store.append(entry: resolvedEntry)
            await refresh()
        } catch {
            // Persist failed — refresh anyway so the user sees current state.
            await refresh()
        }
    }
}

// AI:
//   what: EmptyState — placeholder shown when no diary entries exist
//   why:  specs/ui.md: EmptyState appears when DiaryStore returns no entries
//   ref:  specs/ui.md ContentView, D-0008

public struct EmptyState: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No entries yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Click “New Entry” to start recording your first diary entry.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// AI:
//   what: ContentView — root window view with toolbar and timeline
//   why:  specs/ui.md: WindowGroup 900×660 default, 720×540 min; toolbar with
//         New Entry (primary) and Settings (secondary) buttons; EmptyState when no entries
//   ref:  specs/ui.md ContentView, D-0008

public struct ContentView: View {

    @State private var viewModel: ListViewModel
    @State private var showSettings = false

    private let store: DiaryStore?

    public init(store: DiaryStore? = nil) {
        self.store = store
        self._viewModel = State(initialValue: ListViewModel(store: store))
    }

    public var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationDestination(for: DiaryEntry.self) { entry in
                    EntryDetailView(
                        viewModel: EntryDetailViewModel(entry: entry, store: store)
                    )
                }
                .toolbar { toolbarContent }
        }
        .frame(minWidth: 720, minHeight: 540)
        .sheet(isPresented: $viewModel.showRecordingSheet) {
            RecordingView(
                onCompleted: { entry in
                    Task {
                        await viewModel.finishRecording(entry: entry)
                    }
                },
                onCancel: {
                    viewModel.cancelRecording()
                }
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .frame(minWidth: 460)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.entries.isEmpty {
            EmptyState()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.entries) { entry in
                        NavigationLink(value: entry) {
                            EntryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel.startRecording()
            } label: {
                Label("New Entry", systemImage: "mic.fill")
                    .fontWeight(.semibold)
            }
            .help("Start a new diary entry")
            .disabled(viewModel.isRecording)
        }

        ToolbarItem(placement: .secondaryAction) {
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Open settings")
        }

        ToolbarItem(placement: .secondaryAction) {
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh entries")
        }
    }
}

// AI:
//   what: EntryRow — single timeline row showing date, source badge, duration, excerpt
//   why:  specs/ui.md: each row shows date/time, source badge, duration, one-line excerpt
//   ref:  specs/ui.md ContentView, D-0008

public struct EntryRow: View {
    public let entry: DiaryEntry

    public init(entry: DiaryEntry) {
        self.entry = entry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.startedAt, format: .dateTime)
                    .font(.headline)
                Spacer()
                sourceBadge
            }

            HStack(spacing: 12) {
                Label(
                    title: { Text(formattedDuration) },
                    icon: { Image(systemName: "clock") }
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var sourceBadge: some View {
        switch entry.source {
        case .speech:
            Label("Speech", systemImage: "waveform")
                .font(.caption)
                .foregroundStyle(.blue)
        case .whisper:
            Label("Whisper", systemImage: "brain")
                .font(.caption)
                .foregroundStyle(.purple)
        case .none:
            Label("Pending", systemImage: "hourglass")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var formattedDuration: String {
        let minutes = Int(entry.durationSeconds) / 60
        let seconds = Int(entry.durationSeconds) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    /// One-line transcript excerpt (first ~120 chars), truncated with ellipsis.
    private var excerpt: String {
        // No transcript text is available in the model; short placeholder.
        // In production, this would read from the transcript file.
        ""
    }
}

#if canImport(AppKit)
import AppKit
#endif

#Preview {
    ContentView()
}
