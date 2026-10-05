import SwiftUI

// AI:
//   what: RecordingView — modal sheet for live audio recording with transcript preview
//   why:  specs/ui.md RecordingView: modal sheet, not dismissible while recording;
//         Start/Stop toggle, live transcript, Finalizing state, auto-dismiss on completion
//   ref:  specs/ui.md RecordingView, D-0004, D-0008

public struct RecordingView: View {

    @State private var viewModel: RecordingViewModel
    @State private var hasCancelled = false
    @Environment(\.dismiss) private var dismiss

    /// Called when recording completes with the finished `DiaryEntry` plus the final
    /// `Transcript` produced by the post-recording transcription pipeline (or nil if
    /// transcription yielded no final transcript, e.g. failure or no service wired).
    /// The caller (e.g., ListViewModel via `finishRecording`) copies the audio + transcript
    /// into the store folder and persists both via `append` then `setTranscript`.
    //
    // AI: PRD #40 — `transcriptionFailureMessage` carries a human-readable message when the
    //     post-recording transcription pipeline failed (e.g. networkUnavailable). It's passed
    //     alongside entry/transcript so finishRecording can surface it through the
    //     ListViewModel.errorBanner pathway (defined by PRD #25) — the entry + audio are
    //     still persisted (audio is never lost), but the user sees the failure reason
    //     rather than a silent empty transcript.
    //     ref: PRD 40-ats-handling-audit (requirement 3)
    private var onCompleted: ((DiaryEntry, Transcript?, String?) -> Void)?
    private var onCancel: (() -> Void)?

    public init(
        viewModel: RecordingViewModel = RecordingViewModel(),
        onCompleted: ((DiaryEntry, Transcript?, String?) -> Void)? = nil,
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
            // AI: PRD #22 — visible Cancel/Close button in all states.
            //     During recording: labeled "Cancel", triggers onCancel.
            //     During finalizing: disabled.
            //     After completion (briefly visible): labeled "Close".
            //     After a failed start: labeled "Close", enables dismissal.
            cancelButton
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
            //
            // AI: PRD #40 — when the post-recording transcription pipeline failed (e.g.
            //     networkUnavailable), completedEntry is still set (audio is never lost)
            //     but completedTranscript is nil and transcriptionError carries the
            //     failure reason. We forward it on completion so `finishRecording` can
            //     surface it through `ListViewModel.errorBanner` instead of letting the
            //     sheet auto-dismiss into a silent empty-transcript state.
            //     ref: PRD 40-ats-handling-audit (requirement 3)
            if let entry = newValue {
                let errorToForward = viewModel.transcriptionError.isEmpty
                    ? nil
                    : viewModel.transcriptionError
                onCompleted?(entry, viewModel.completedTranscript, errorToForward)
                dismiss()
            }
        }
        // AI: PRD #22 + PRD #24 — fallback for external dismissal (window close,
        //     Escape via toolbar, sheet swipe). If completedEntry is nil (not
        //     auto-dismissed via onChange), ensure the recording is torn down,
        //     any partial .m4a is removed, and onCancel is invoked to reset
        //     ListViewModel state. PRD #24 additionally calls `teardown()` so the
        //     periodic `timer` Task and `liveStreamTask` are cancelled & nilled
        //     here in every dismissal path — whether the recording completed,
        //     was in progress, or was mid-finalize — so no Task lingers in the
        //     heap referencing the discarded view-model.
        .onDisappear {
            // AI: Always tear down the view-model's background Tasks. This is safe
            //     to call from any state (idle, recording, finalizing) and is
            //     idempotent; `teardown()` guards every internal step.
            //     `.onDisappear` is synchronous, so we wrap the async teardown in a
            //     detached MainActor Task. The Task-cancellation work inside
            //     teardown runs synchronously before its first await, so the
            //     dangerous side-effectful work happens immediately on dismissal;
            //     the subsequent recorder.stop() completes off the dismiss path.
            Task { @MainActor [viewModel] in
                await viewModel.teardown()
            }

            guard !hasCancelled, viewModel.completedEntry == nil else { return }
            hasCancelled = true
            let outputURL = viewModel.handle?.outputURL
            RecordingViewModel.removePartialFile(at: outputURL)
            onCancel?()
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

    // MARK: - Cancel / Close Button

    // AI:
    //   what: cancelButton — secondary action below the start/stop button
    //   why:  PRD #22 — a visible Cancel/Close button reachable during the
    //         recording state (and all other states) so the user can abort
    //         or close the sheet without hunting for the toolbar action.
    //         During recording: labeled "Cancel" and calls onCancel after
    //         tearing down the recording.
    //         During finalizing: disabled (the pipeline must complete).
    //         After completion: labeled "Close" (briefly visible before
    //         auto-dismiss via onChange).
    //         After a failed start: labeled "Close", enabled for manual dismissal.
    //   ref:  PRD 22-recording-sheet-cancel-clear
    private var cancelButton: some View {
        Button {
            cancel()
        } label: {
            Text(viewModel.isRecording ? "Cancel" : "Close")
                .font(.body)
                .padding(.horizontal, 24)
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.isFinalizing)
    }

    /// Halt recording, clean up partial files, and invoke `onCancel`.
    /// Called by the Cancel/Close button. Guarded by `hasCancelled` so the
    /// `.onDisappear` fallback doesn't double-fire `onCancel`.
    private func cancel() {
        guard !hasCancelled else { return }
        hasCancelled = true

        let outputURL = viewModel.handle?.outputURL
        let hasCompletedEntry = viewModel.completedEntry != nil

        Task { @MainActor in
            await viewModel.cancelRecording()
            // Delete any partial .m4a file only when no entry was completed
            // (i.e., the recording is being discarded, not finalized).
            if !hasCompletedEntry {
                RecordingViewModel.removePartialFile(at: outputURL)
            }
            onCancel?()
        }

        dismiss()
    }
}

#if canImport(AppKit)
import AppKit
#endif

#Preview {
    RecordingView()
}
