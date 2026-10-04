import XCTest
@testable import DiaryTranscriberCore

final class FileSystemWatcherTests: XCTestCase {

    @MainActor
    func testWatch_emitsWhenFileCreated() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "watch-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let watcher = FileSystemWatcher(folder: tempDir)

        let stream = await watcher.watch()

        // Give the watcher time to take its initial snapshot.
        try await Task.sleep(for: .milliseconds(600))

        // Create a file to trigger the change.
        let testFile = tempDir.appending(path: "test-entry-\(UUID().uuidString).m4a")
        try "fake audio".write(to: testFile, atomically: true, encoding: .utf8)

        // Collect at most 1 update with a timeout.
        var urls: [URL] = []
        let collectTask = Task {
            for await url in stream {
                urls.append(url)
                if urls.count >= 1 { break }
            }
        }

        // Poll for completion up to 5 seconds.
        for _ in 0..<50 {
            if !urls.isEmpty { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        collectTask.cancel()

        XCTAssertFalse(urls.isEmpty, "Watcher should emit after file creation")
        await watcher.stop()
    }

    @MainActor
    func testWatch_emitsWhenFileDeleted() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "watch-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Pre-create a file.
        let testFile = tempDir.appending(path: "to-delete-\(UUID().uuidString).m4a")
        try "fake audio".write(to: testFile, atomically: true, encoding: .utf8)

        let watcher = FileSystemWatcher(folder: tempDir)
        let stream = await watcher.watch()

        // Give the watcher time to take its initial snapshot.
        try await Task.sleep(for: .milliseconds(600))

        // Delete the file to trigger the change.
        try FileManager.default.removeItem(at: testFile)

        // Collect at most 1 update with a timeout.
        var urls: [URL] = []
        let collectTask = Task {
            for await url in stream {
                urls.append(url)
                if urls.count >= 1 { break }
            }
        }

        for _ in 0..<50 {
            if !urls.isEmpty { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        collectTask.cancel()

        XCTAssertFalse(urls.isEmpty, "Watcher should emit after file deletion")
        await watcher.stop()
    }

    @MainActor
    func testStop_isIdempotent() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "watch-stop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let watcher = FileSystemWatcher(folder: tempDir)
        _ = await watcher.watch()
        await watcher.stop()
        // Calling stop() again should not crash.
        await watcher.stop()
    }
}
