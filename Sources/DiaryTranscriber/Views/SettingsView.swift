import SwiftUI

// AI:
//   what: SettingsView sheet for output folder, mic picker, and transcription settings
//   why:  specs/ui.md SettingsView; API key in Keychain (dots), folder via NSOpenPanel,
//         mic via Picker listing AVCaptureDevice.audio devices
//   ref:  specs/ui.md SettingsView, D-0004

public struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel: SettingsViewModel
    // AI: local buffer for the API-key field; SecureField binds here, not to Keychain, so each keystroke
    //     only mutates this @State and never touches SecItem; commitAPIKey persists it on demand / PRD 30
    @State private var apiKeyInput: String = ""

    public init(viewModel: SettingsViewModel = SettingsViewModel()) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        Form {
            Section("General") {
                LabeledContent("Output Folder") {
                    HStack {
                        Text(viewModel.outputFolder)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") {
                            chooseFolder()
                        }
                    }
                }

                Picker("Default Microphone", selection: Binding(
                    get: { viewModel.micID },
                    set: { viewModel.micID = $0 }
                )) {
                    ForEach(viewModel.availableMics, id: \.id) { mic in
                        Text(mic.name).tag(mic.id as String)
                    }
                }
            }

            Section("Transcription") {
                Toggle("Use on-device Speech", isOn: Binding(
                    get: { viewModel.transcriptionSettings.useOnDeviceSpeech },
                    set: { viewModel.transcriptionSettings.useOnDeviceSpeech = $0 }
                ))

                Toggle("Fall back to Whisper API", isOn: Binding(
                    get: { viewModel.transcriptionSettings.useWhisperFallback },
                    set: { viewModel.transcriptionSettings.useWhisperFallback = $0 }
                ))

                // AI: bind SecureField to local @State apiKeyInput so typing never hits Keychain; commit
                //     happens on .onSubmit, .onDisappear, or explicit Save only / PRD 30
                SecureField("OpenAI API Key", text: $apiKeyInput)
                    .onSubmit {
                        // AI: commit on Return so a user who submits the field persists immediately / PRD 30.
                        //     PRD #28: after commit, rebuild the WhisperClient on the shared service so the
                        //     new key takes effect without restarting the app (criterion 2).
                        viewModel.commitAPIKey(apiKeyInput)
                        env.reloadWhisperClient()
                    }

                // AI: explicit Save button so a user can persist the buffered key without leaving / PRD 30.
                //     PRD #28: same reload as .onSubmit — the Whisper fallback must pick up the new key.
                Button("Save API Key") {
                    viewModel.commitAPIKey(apiKeyInput)
                    env.reloadWhisperClient()
                }
            }

            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Bundle ID", value: "com.compactifai.diarytranscriber")
            }
        }
        .padding()
        .frame(minWidth: 420)
        .onAppear {
            // AI: load the current Keychain value into the buffer exactly once on view appearance;
            //     never re-read per keystroke, so display and buffer never desync / PRD 30
            apiKeyInput = viewModel.apiKey
        }
        .onDisappear {
            // AI: persist toggles to UserDefaults and commit any buffered-but-unsubmitted API key
            //     when the sheet closes — single write path, no per-keystroke Keychain churn / PRD 29, PRD 30.
            //     PRD #28: reload the Whisper fallback so a dialog dismissed after Save keeps the new key.
            viewModel.commitAPIKey(apiKeyInput)
            viewModel.save()
            env.reloadWhisperClient()
        }
    }

    private func chooseFolder() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose Diary Output Folder"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.outputFolder = url.path
        }
        #endif
    }
}

#if canImport(AppKit)
import AppKit
#endif

#Preview {
    SettingsView()
        .environment(AppEnvironment())
}
