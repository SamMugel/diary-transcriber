import SwiftUI

// AI:
//   what: SettingsView sheet for output folder, mic picker, and transcription settings
//   why:  specs/ui.md SettingsView; API key in Keychain (dots), folder via NSOpenPanel,
//         mic via Picker listing AVCaptureDevice.audio devices
//   ref:  specs/ui.md SettingsView, D-0004

public struct SettingsView: View {
    @State private var viewModel: SettingsViewModel

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

                SecureField("OpenAI API Key", text: Binding(
                    get: { viewModel.apiKey },
                    set: { viewModel.apiKey = $0 }
                ))
            }

            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Bundle ID", value: "com.compactifai.diarytranscriber")
            }
        }
        .padding()
        .frame(minWidth: 420)
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
