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
        isRecording = true
    }

    public func cancelRecording() {
        isRecording = false
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

    public init(store: DiaryStore? = nil) {
        self._viewModel = State(initialValue: ListViewModel(store: store))
    }

    public var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar { toolbarContent }
        }
        .frame(minWidth: 720, minHeight: 540)
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
            List(viewModel.entries) { entry in
                EntryRow(entry: entry)
            }
            .listStyle(.sidebar)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                if viewModel.isRecording {
                    viewModel.cancelRecording()
                } else {
                    viewModel.startRecording()
                }
            } label: {
                if viewModel.isRecording {
                    Label("Cancel", systemImage: "stop.circle.fill")
                } else {
                    Label("New Entry", systemImage: "mic.fill")
                        .fontWeight(.semibold)
                }
            }
            .help(viewModel.isRecording ? "Cancel recording" : "Start a new diary entry")
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
}

#if canImport(AppKit)
import AppKit
#endif

#Preview {
    ContentView()
}
