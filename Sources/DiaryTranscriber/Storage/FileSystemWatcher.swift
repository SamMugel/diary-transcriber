import Foundation

// AI:
//   what: FileSystemWatcher observes the Diary output folder for changes
//   why:  PRD 10: new .m4a files appear in timeline within 2s; deletions remove
//         entries within 2s; burst writes (10 files/1s) debounced to at most 2 refreshes
//   ref:  specs/architecture.md FileSystemWatcher, D-0005

public actor FileSystemWatcher {

    private let folder: URL
    private let pollInterval: TimeInterval = 0.5
    private var pollTask: Task<Void, Never>?
    private var lastSnapshot: Set<String> = []
    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: TimeInterval = 0.5

    public init(folder: URL) {
        self.folder = folder
    }

    // MARK: - Public API

    /// Watch the folder and emit the folder URL for each debounced change.
    public func watch() -> AsyncStream<URL> {
        AsyncStream { continuation in
            let task = Task {
                await self.startPolling(continuation: continuation)
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { await self.stop() }
            }
        }
    }

    /// Stop observing the folder.
    public func stop() async {
        pollTask?.cancel()
        pollTask = nil
        debounceTask?.cancel()
        debounceTask = nil
    }

    // MARK: - Private: Polling

    private func startPolling(
        continuation: AsyncStream<URL>.Continuation
    ) async {
        // Initial snapshot.
        lastSnapshot = currentFileSet()

        pollTask = Task {
            while !Task.isCancelled {
                let nanos = UInt64(pollInterval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)

                if Task.isCancelled { break }

                let snapshot = currentFileSet()
                if snapshot != lastSnapshot {
                    lastSnapshot = snapshot
                    scheduleDebouncedRefresh(continuation: continuation)
                }
            }
            continuation.finish()
        }
    }

    private func scheduleDebouncedRefresh(
        continuation: AsyncStream<URL>.Continuation
    ) {
        // Cancel any existing debounce timer to absorb bursts.
        debounceTask?.cancel()

        debounceTask = Task {
            let nanos = UInt64(debounceInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)

            if !Task.isCancelled {
                continuation.yield(folder)
            }
        }
    }

    // MARK: - Private: File listing

    private nonisolated func currentFileSet() -> Set<String> {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        var fileNames = Set<String>()
        for entry in entries {
            // Ignore hidden files (e.g., .manifest.tmp) and directories.
            let name = entry.lastPathComponent
            if !name.hasPrefix(".") {
                fileNames.insert(name)
            }
        }
        return fileNames
    }
}
