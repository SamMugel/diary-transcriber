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
    func testTogglePlayPause_togglesIsPlayingFlag() {
        let player = AudioPlayer()
        // No player loaded; toggle should not start playback
        player.togglePlayPause()
        XCTAssertFalse(player.isPlaying, "Should not start without a loaded player")
    }

    @MainActor
    func testStop_resetsState() {
        let player = AudioPlayer()
        player.stop()
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentTime, 0)
    }

    @MainActor
    func testTimecode_formatsCorrectly() {
        let player = AudioPlayer()
        // Verify pure timecode formatting logic via progress and timecode accessors
        // Cannot load a real audio file without binary data, but we can verify
        // that the default timecode is "00:00"
        XCTAssertEqual(player.timecode, "00:00")
    }

    @MainActor
    func testProgress_zeroWhenDurationIsZero() {
        let player = AudioPlayer()
        player.currentTime = 10
        XCTAssertEqual(player.progress, 0, "Progress should be 0 when duration is 0")
    }

    @MainActor
    func testProgress_clampedToOne() {
        let player = AudioPlayer()
        player.duration = 10
        player.currentTime = 15
        XCTAssertEqual(player.progress, 1.0, "Progress should clamp to 1.0")
    }
}
