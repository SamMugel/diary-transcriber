import SwiftUI

public struct ContentView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Diary Transcriber")
                .font(.largeTitle)
            Text("No entries yet")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}
