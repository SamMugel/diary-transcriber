import SwiftUI

// AI:
//   what: RecordingView — modal sheet for live audio recording with transcript preview
//   why:  specs/ui.md RecordingView: modal sheet, not dismissible while recording;
//         Start/Stop toggle, live transcript, Finalizing state, auto-dismiss on completion
//   ref:  specs/ui.md RecordingView, D-0004, D-0008

public struct RecordingView: View {

    @State private var viewModel: RecordingViewModel
    @Environment(\.dismiss) private var dismiss

    /// Called when recording completes with the finished `DiaryEntry` plus the final
    /// `Transcript` produced by the post-recording transcription pipeline (or nil if
    /// transcription yielded no final transcript, e.g. failure or no service wired).
    /// The caller (e.g., ListViewModel via `finishRecording`) copies the audio + transcript
    /// into the store folder and persists both via `append` then `setTranscript`.
    // AI: PRD #18 — `onCompleted` now carries the Transcript so `finishRecording` can call
    //     `store.setTranscript` AFTER `store.append` creates the manifest row (setTranscript
    //     requires the row to exist — `stop()` cannot call it directly because the manifest
    //     entry is only created downstream in `finishRecording`).
    private var onCompleted: ((DiaryEntry, Transcript?) -> Void)?
    private var onCancel: (() -> Void)?

    public init(
        viewModel: RecordingViewModel = RecordingViewModel(),
        onCompleted: ((DiaryEntry, Transcript?) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.onCompleted = onCompleted
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 24) {
            header
            timer
            startStopButton
            if !viewModel.permissionMessage.isEmpty {
                permissionBanner
            }
            transcriptArea
            if viewModel.isFinalizing {
                finalizingIndicator
            }
        }
        .padding(32)
        .frame(minWidth: 480, minHeight: 400)
        .interactiveDismissDisabled(viewModel.isRecording || viewModel.isFinalizing)
        .task {
            // Auto-start recording when the sheet appears.
            await viewModel.start()
        }
        .onChange(of: viewModel.completedEntry) { _, newValue in
            // Auto-dismiss when the entry is committed (non-nil) to the view-model,
            // which happens after stop() completes. The matching Transcript (if any)
            // is propagated to `onCompleted` so the downstream `finishRecording` can
            // persist it via `store.setTranscript` after `store.append`.
            if let entry = newValue {
                onCompleted?(entry, viewModel.completedTranscript)
                dismiss()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        Text("New Diary Entry")
            .font(.title2)
            .fontWeight(.semibold)
    }

    // MARK: - Timer

    private var timer: some View {
        Text(formattedElapsed)
            .font(.system(.title, design: .monospaced))
            .foregroundStyle(
                viewModel.isRecording ? Color.red : Color.secondary
            )
    }

    private var formattedElapsed: String {
        let total = Int(viewModel.elapsed)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Start / Stop Button

    private var startStopButton: some View {
        Button {
            Task {
                if viewModel.isRecording {
                    await viewModel.stop()
                } else {
                    await viewModel.start()
                }
            }
        } label: {
            Label(
                viewModel.isRecording ? "Stop" : "Start",
                systemImage: viewModel.isRecording
                    ? "stop.circle.fill"
                    : "mic.fill"
            )
            .font(.headline)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.isRecording ? .red : .accentColor)
        .disabled(viewModel.isFinalizing)
    }

    // MARK: - Transcript Area

    private var transcriptArea: some View {
        ScrollView {
            Text(viewModel.liveTranscript.isEmpty
                ? "Live transcript will appear here…"
                : viewModel.liveTranscript)
                .font(.body)
                .foregroundStyle(
                    viewModel.liveTranscript.isEmpty
                        ? Color.secondary
                        : Color.primary
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Permission Banner

    private var permissionBanner: some View {
        VStack(spacing: 8) {
            Text(viewModel.permissionMessage)
                .font(.body)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open System Settings") {
                openMicrophoneSettings()
            }
            .buttonStyle(.bordered)
        }
    }

    private func openMicrophoneSettings() {
        #if canImport(AppKit)
        // AI: Open System Settings → Privacy & Security → Microphone using
        //     a safe navigation URL; falls gracefully if the OS version
        //     differs from expected.
        let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Microphone"
        )
        if let settingsURL {
            NSWorkspace.shared.open(settingsURL)
        }
        #endif
    }

    // MARK: - Finalizing

    private var finalizingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Finalizing…")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .transition(.opacity)
    }
}

#if canImport(AppKit)
import AppKit
#endif

#Preview {
    RecordingView()
}
