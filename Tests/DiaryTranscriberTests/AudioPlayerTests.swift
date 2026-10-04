import XCTest
@testable import DiaryTranscriberCore

final class AudioPlayerTests: XCTestCase {

    @MainActor
    func testInitialState_noPlayerLoaded() {
        let player = AudioPlayer()
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.duration, 0)
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertEqual(player.progress, 0)
        XCTAssertEqual(player.timecode, "00:00")
    }

    @MainActor
    func testTogglePlayPause_noPlayerLoaded_doesNothing() {
        let player = AudioPlayer()
        // Without a loaded AVAudioPlayer, toggle should be a no-op.
        player.togglePlayPause()
        XCTAssertFalse(player.isPlaying, "Should not start without a loaded player")
        player.togglePlayPause()
        XCTAssertFalse(player.isPlaying, "Still no player; should remain stopped")
    }

    @MainActor
    func testStop_resetsCurrentTimeToZero() {
        let player = AudioPlayer()
        // Set non-default state, then verify stop resets it.
        player.currentTime = 30
        player.duration = 60
        player.isPlaying = true
        player.stop()
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentTime, 0, "stop() should reset currentTime to 0")
    }

    @MainActor
    func testTimecode_formatsMinutesAndSeconds() {
        let player = AudioPlayer()

        player.currentTime = 0
        XCTAssertEqual(player.timecode, "00:00")

        player.currentTime = 5
        XCTAssertEqual(player.timecode, "00:05")

        player.currentTime = 65
        XCTAssertEqual(player.timecode, "01:05")

        player.currentTime = 125.7
        XCTAssertEqual(player.timecode, "02:05", "Fractional seconds should truncate")

        player.currentTime = 3599
        XCTAssertEqual(player.timecode, "59:59")
    }

    @MainActor
    func testProgress_zeroWhenDurationIsZero() {
        let player = AudioPlayer()
        player.currentTime = 10
        XCTAssertEqual(player.progress, 0, "Progress should be 0 when duration is 0")
    }

    @MainActor
    func testProgress_calculatesRatio() {
        let player = AudioPlayer()
        player.duration = 100
        player.currentTime = 50
        XCTAssertEqual(player.progress, 0.5, accuracy: 0.001, "Progress at 50/100 should be 0.5")
    }

    @MainActor
    func testProgress_clampedToOne() {
        let player = AudioPlayer()
        player.duration = 10
        player.currentTime = 15
        XCTAssertEqual(player.progress, 1.0, "Progress should clamp to 1.0")
    }
}
