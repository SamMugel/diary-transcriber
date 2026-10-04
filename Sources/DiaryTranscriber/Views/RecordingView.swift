import SwiftUI

// AI:
//   what: RecordingView — modal sheet for live audio recording with transcript preview
//   why:  specs/ui.md RecordingView: modal sheet, not dismissible while recording;
//         Start/Stop toggle, live transcript, Finalizing state, auto-dismiss on completion
//   ref:  specs/ui.md RecordingView, D-0004, D-0008

public struct RecordingView: View {

    @State private var viewModel: RecordingViewModel
    @Environment(\.dismiss) private var dismiss

    private var onCompleted: (() -> Void)?

    public init(
        viewModel: RecordingViewModel = RecordingViewModel(),
        onCompleted: (() -> Void)? = nil
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.onCompleted = onCompleted
    }

    public var body: some View {
        VStack(spacing: 24) {
            header
            timer
            startStopButton
            transcriptArea
            if viewModel.isFinalizing {
                finalizingIndicator
            }
        }
        .padding(32)
        .frame(minWidth: 480, minHeight: 400)
        .interactiveDismissDisabled(viewModel.isRecording || viewModel.isFinalizing)
        .onChange(of: viewModel.isFinalizing) { _, newValue in
            // Auto-dismiss when finalization completes (transitions to false).
            if !newValue && viewModel.handle == nil {
                onCompleted?()
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
