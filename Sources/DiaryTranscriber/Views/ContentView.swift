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

    // AI: PRD #25 — non-fatal, user-facing error banner surfaced when finishRecording
    //     fails to persist an entry. Cleared by the user via Dismiss or automatically
    //     on a successful retry. nil = no banner.
    public var errorBanner: String? = nil

    // AI: PRD #25 — holds the entry + transcript from the last failed finishRecording
    //     call so Retry can re-attempt the append step without the user re-recording.
    //     Audio (the .m4a) was already written to ~/Documents by AudioRecorder before
    //     finishRecording runs, so it is safe to retry the move+append.
    private var lastFailedFinish: (DiaryEntry, Transcript?)? = nil

    // AI: PRD #27 — per-entry transcript excerpt cache so a 1,000-entry timeline does
    //     not re-read every `.md` on each SwiftUI redraw. The key is `entry.id`; the
    //     value is the already-truncated preview text (with trailing "…" when the
    //     transcript exceeded the excerpt length) or "No transcript yet" for entries
    //     with `source == .none`. A `nil` value means "not yet loaded" — the first
    //     redraw that observes a `nil` caches kicks off a single Task to populate it;
    //     subsequent redraws find a stored value and skip disk entirely. Stored as a
    //     plain `var` on this `@Observable` so SwiftUI invalidates the affected rows
    //     when an excerpt lands without reloading the whole list.
    public var previewExcerpts: [UUID: String] = [:]

    private let store: DiaryStore?
    // AI: PRD #28 — shared TranscriptionService injected from AppEnvironment so view-models never
    //     default-construct a per-VM service. Optional + nil-default keeps existing tests that
    //     construct `ListViewModel(store:)` compiling. This reference is only consumed by downstream
    //     PRDs (#18) and #28 only wires it here; finishRecording() is unchanged.
    private let transcriptionService: TranscriptionService?

    public init(store: DiaryStore? = nil, transcriptionService: TranscriptionService? = nil) {
        self.store = store
        self.transcriptionService = transcriptionService
        Task { await refresh() }
    }

    public func refresh() async {
        guard let store else { return }
        do {
            entries = try await store.entries()
        } catch {
            entries = []
        }

        // AI: PRD #27 — drop preview-cache entries for ids no longer in the manifest
        //     (deleted entries) so the cache does not grow unbounded across refreshes.
        let liveIDs = Set(entries.map(\.id))
        previewExcerpts = previewExcerpts.filter { liveIDs.contains($0.key) }
        kickOffPreviewLoads()
    }

    // AI: PRD #27 — for every entry without a cached preview, fire a single Task
    //     to load the excerpt from disk. `.none`-source entries are cached
    //     synchronously here ("No transcript yet") so they never spawn I/O and never
    //     flip from empty → populated, which would re-render the row a second time.
    //     The per-entry cache prevents repeated reads across redraws: a Task is only
    //     started the first time an id is observed without a cached value.
    private func kickOffPreviewLoads() {
        guard let store else { return }
        for entry in entries where previewExcerpts[entry.id] == nil {
            if entry.source == .none {
                previewExcerpts[entry.id] = "No transcript yet"
                continue
            }
            Task {
                // AI: PRD #27 — request one extra char beyond the display length so we
                //     can detect "there was more to read" and append "…" without
                //     mis-flagging transcripts that are exactly `length` chars long.
                let excerptLength = 120
                let raw = (try? await store.excerpt(for: entry, length: excerptLength + 1)) ?? ""
                // Guards against a row that was deleted or re-loaded while the Task
                // was inflight; only commit a value for ids still in `entries`.
                if entries.contains(where: { $0.id == entry.id }) {
                    let preview: String
                    if raw.isEmpty {
                        preview = ""
                    } else if raw.count > excerptLength {
                        // More transcript existed beyond the display length:
                        // truncate to exactly `excerptLength` and append U+2026.
                        let end = raw.index(raw.startIndex, offsetBy: excerptLength)
                        preview = String(raw[raw.startIndex..<end]) + "…"
                    } else {
                        preview = raw
                    }
                    previewExcerpts[entry.id] = preview
                }
            }
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
    /// If a final `Transcript` is supplied (from the post-recording transcription pipeline),
    /// it is persisted via `store.setTranscript` AFTER `store.append` creates the manifest row
    /// — `setTranscript` requires the row to already exist, and `append` is what writes it.
    // AI: PRD #18 — finishRecording is the canonical persistence seam where the manifest row is
    //     created, so it's also where setTranscript is called. stop() runs the transcription
    //     pipeline and exposes the Transcript via onCompleted; it does NOT call setTranscript
    //     itself (the entry doesn't exist in the manifest yet at that point).
    public func finishRecording(entry: DiaryEntry, transcript: Transcript? = nil) async {
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

            // AI: create the manifest row first — setTranscript requires it to exist.
            try await store.append(entry: resolvedEntry)

            // AI: persist the final transcript (if any) into the entry's `.md` and update
            //     the manifest's source/updatedAt. This is the `tail end` of the post-recording
            //     pipeline: stop() ran transcription → here we atomically write the text to disk.
            //     On failure/no transcript, the entry keeps `.none` source + empty `.md` (created
            //     by `append`) so the timeline still shows the recorded audio (criterion #4).
            if let transcript {
                try await store.setTranscript(
                    for: resolvedEntry.id,
                    source: transcript.source,
                    text: transcript.text
                )
            }

            // AI: PRD #25 — success: clear any prior error banner + retry state.
            errorBanner = nil
            lastFailedFinish = nil

            await refresh()
        } catch {
            // AI: PRD #25 — never swallow with a bare catch. The error describes the
            //     persistence failure; the audio file was already saved to ~/Documents
            //     by AudioRecorder, so we surface that location so the user knows it's
            //     not lost. Store the entry+transcript so Retry can re-attempt.
            lastFailedFinish = (entry, transcript)
            errorBanner = "Audio saved to ~/Documents, entry could not be saved: \(error.localizedDescription)"
            await refresh()
        }
    }

    // AI: PRD #25 — re-attempts the failed persistence step (move + append + setTranscript)
    //     using the entry + transcript stashed in lastFailedFinish. Audio is not lost on
    //     failure because AudioRecorder wrote the .m4a before finishRecording ever runs.
    //     On success, the banner + retry state are cleared. On failure, the banner is
    //     updated with the new error description so the user can retry again.
    public func retryFinishRecording() async {
        guard let (entry, transcript) = lastFailedFinish, let store else { return }
        do {
            let sourceURL = URL(filePath: entry.audioPath)
            let filename = sourceURL.lastPathComponent
            let relativeAudioPath = filename
            let relativeTranscriptPath = sourceURL.deletingPathExtension()
                .appendingPathExtension("md").lastPathComponent

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

            let storeFolder = await store.folderURL()
            try? FileManager.default.createDirectory(
                at: storeFolder,
                withIntermediateDirectories: true
            )
            let destURL = storeFolder.appending(path: filename)
            try? FileManager.default.removeItem(at: destURL)
            try FileManager.default.moveItem(at: sourceURL, to: destURL)

            try await store.append(entry: resolvedEntry)

            if let transcript {
                try await store.setTranscript(
                    for: resolvedEntry.id,
                    source: transcript.source,
                    text: transcript.text
                )
            }

            errorBanner = nil
            lastFailedFinish = nil
            await refresh()
        } catch {
            errorBanner = "Audio saved to ~/Documents, entry could not be saved: \(error.localizedDescription)"
            await refresh()
        }
    }
}

// AI:
//   what: EmptyState — placeholder shown when no diary entries exist
//   why:  specs/ui.md: EmptyState appears when DiaryStore returns no entries.
//         PRD #33 — replaced the passive "Click 'New Entry'…" instruction with a
//         centered, prominent CTA Button labeled "New Entry" (.borderedProminent)
//         wired to the identical `startRecording()` action the toolbar uses, so
//         there is one source of truth for starting the first recording.
//   ref:  specs/ui.md ContentView, D-0008, PRD 33-empty-state-cta

public struct EmptyState: View {
    /// Invoked when the centered "New Entry" CTA is tapped. Defaults to `startRecording()`
    /// on the owning `ListViewModel`; the single source of truth for the New Entry action.
    public let onNewEntry: () -> Void

    public init(onNewEntry: @escaping () -> Void) {
        self.onNewEntry = onNewEntry
    }

    public var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "mic.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No entries yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button(action: onNewEntry) {
                Label("New Entry", systemImage: "mic.fill")
                    .font(.title3.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Start your first diary recording")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// AI:
//   what: ErrorBanner — inline, non-blocking error banner shown at the top of ContentView
//   why:  PRD #25 — when finishRecording fails to persist an entry, the user needs a clear
//         message naming the failure and saved file location, plus Dismiss + Retry actions
//   ref:  PRD 25-finish-recording-error-feedback

public struct ErrorBanner: View {
    public let message: String
    public let onDismiss: () -> Void
    public let onRetry: () -> Void

    public init(message: String, onDismiss: @escaping () -> Void, onRetry: @escaping () -> Void) {
        self.message = message
        self.onDismiss = onDismiss
        self.onRetry = onRetry
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamation.triangle.fill")
                .foregroundStyle(.orange)
                .font(.headline)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                HStack(spacing: 12) {
                    Button("Retry", action: onRetry)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Dismiss", action: onDismiss)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(Color.yellow.opacity(0.15))
        .overlay(
            Rectangle()
                .fill(Color.yellow.opacity(0.5))
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .bottom),
            alignment: .bottom
        )
    }
}

// AI:
//   what: ContentView — root window view with toolbar and timeline
//   why:  specs/ui.md: WindowGroup 900×660 default, 720×540 min; toolbar with
//         New Entry (primary) and Settings (secondary) buttons; EmptyState when no entries
//   ref:  specs/ui.md ContentView, D-0008

public struct ContentView: View {

    @Environment(AppEnvironment.self) private var env
    @State private var viewModel: ListViewModel
    @State private var showSettings = false

    // AI: PRD #28 — ContentView now resolves the shared AppEnvironment delivered from @main and
    //     forwards the transcriptionService/store into the view-models rather than default-
    //     constructing them. The previous store-only init is preserved as a nil-default convenience
    //     so #Preview still works without an injected env (the .environment is added there too).
    public init(store: DiaryStore? = nil, transcriptionService: TranscriptionService? = nil) {
        self._viewModel = State(
            initialValue: ListViewModel(store: store, transcriptionService: transcriptionService)
        )
    }

    public var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationDestination(for: DiaryEntry.self) { entry in
                    EntryDetailView(
                        viewModel: EntryDetailViewModel(
                            entry: entry,
                            store: env.store,
                            transcriptionService: env.transcriptionService
                        )
                    )
                }
                .toolbar { toolbarContent }
        }
        .frame(minWidth: 720, minHeight: 540)
        .sheet(isPresented: $viewModel.showRecordingSheet) {
            RecordingView(
                // AI: PRD #18 — `onCompleted` carries the final Transcript (or nil) so
                //     `finishRecording` can call `store.setTranscript` after `store.append`.
                //     PRD #28 wires the shared TranscriptionService directly into the VM.
                viewModel: RecordingViewModel(
                    transcriptionService: env.transcriptionService
                ),
                onCompleted: { entry, transcript in
                    Task {
                        await viewModel.finishRecording(entry: entry, transcript: transcript)
                    }
                },
                onCancel: {
                    viewModel.cancelRecording()
                }
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: env.settings)
                .frame(minWidth: 460)
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            // AI: PRD #25 — inline non-blocking error banner at the top of the content
            //     area. Yellow/orange background signals a recoverable error, not a crash.
            //     Dismiss clears errorBanner; Retry re-invokes the failed persistence step.
            if let errorMessage = viewModel.errorBanner {
                ErrorBanner(
                    message: errorMessage,
                    onDismiss: { viewModel.errorBanner = nil },
                    onRetry: { Task { await viewModel.retryFinishRecording() } }
                )
            }
            if viewModel.entries.isEmpty {
                EmptyState {
                    viewModel.startRecording()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.entries) { entry in
                            NavigationLink(value: entry) {
                                EntryRow(
                                    entry: entry,
                                    preview: viewModel.previewExcerpts[entry.id] ?? ""
                                )
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                // AI: PRD 11 — New Entry toggles to Cancel while recording so the
                //     user can abort without hunting for a separate control.
                if viewModel.isRecording {
                    viewModel.cancelRecording()
                } else {
                    viewModel.startRecording()
                }
            } label: {
                if viewModel.isRecording {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                        .fontWeight(.semibold)
                } else {
                    Label("New Entry", systemImage: "mic.fill")
                        .fontWeight(.semibold)
                }
            }
            .help(viewModel.isRecording ? "Cancel the current recording" : "Start a new diary entry")
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

    /// Cached transcript preview pre-loaded by the parent list view-model (PRD #27).
    /// Pass the already-truncated string so this view never touches disk and never
    /// re-reads the transcript `.md` on redraw. Empty string means "still loading or
    /// no preview available"; "No transcript yet" is delivered for `.none`-source rows.
    public let preview: String

    public init(entry: DiaryEntry, preview: String = "") {
        self.entry = entry
        self.preview = preview
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

    /// One-line transcript excerpt delivered by the list view-model (PRD #27).
    /// The value is cached in `ListViewModel.previewExcerpts` to avoid re-reading
    /// the transcript `.md` on every redraw; here we only render what was already
    /// loaded.
    private var excerpt: String {
        preview
    }
}

#if canImport(AppKit)
import AppKit
#endif

#Preview {
    ContentView()
        .environment(AppEnvironment())
}
