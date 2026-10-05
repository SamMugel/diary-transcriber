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

    // MARK: - cleanup (PRD #31)

    // AI:
    //   what: cleanup resets observable playback state to a quiescent baseline
    //   why:  PRD #31 — `cleanup()` must be safe to call from EntryDetailView.onDisappear.
    //         We can't feed a real AVAudioPlayer in a unit test (needs PCM bytes on disk),
    //         but we can pre-seed isPlaying/currentTime to a mid-playback profile and verify
    //         cleanup leaves everything reset to initial values. This pins the observable
    //         contract that the SwiftUI bindings rely on: `isPlaying = false`,
    //         `currentTime = 0`, `progress = 0` afterwards. The underlying player reference
    //         is private, so we assert via the observable surface.
    //   ref:  PRD 31-audio-player-cleanup.json
    @MainActor
    func testCleanup_resetsPlaybackState() {
        let player = AudioPlayer()
        // Seed a mid-playback profile directly on the observable surface.
        player.currentTime = 42
        player.duration = 60
        player.isPlaying = true

        player.cleanup()

        XCTAssertFalse(player.isPlaying, "cleanup must stop playback")
        XCTAssertEqual(player.currentTime, 0, "cleanup must reset currentTime to 0")
        XCTAssertEqual(player.progress, 0, "cleanup must zero out progress")
    }

    // AI:
    //   what: cleanup is idempotent — calling it twice has no side-effects
    //   why:  PRD #31 acceptance criterion #2 — EntryDetailView.onDisappear fires once, but the
    //         guarantee is reused if the view is re-entered, and SwiftUI can lifecycle the view
    //         with arbitrary onDisappear/onAppear counts. cleanup() must not fault or throw on
    //         repeat invocation. We assert the observable state stays stable across the second
    //         call (no flipped flags, no resurrected playback).
    //   ref:  PRD 31-audio-player-cleanup.json
    @MainActor
    func testCleanup_isIdempotent() {
        let player = AudioPlayer()
        player.currentTime = 18
        player.duration = 90
        player.isPlaying = true

        player.cleanup()
        // Snapshot post-first-call state.
        let isPlayingAfterFirst = player.isPlaying
        let currentTimeAfterFirst = player.currentTime
        let progressAfterFirst = player.progress

        player.cleanup()

        XCTAssertEqual(player.isPlaying, isPlayingAfterFirst, "Second cleanup must not resurrect playback")
        XCTAssertEqual(player.currentTime, currentTimeAfterFirst, "Second cleanup must not change currentTime")
        XCTAssertEqual(player.progress, progressAfterFirst, "Second cleanup must not change progress")
        XCTAssertFalse(player.isPlaying, "Should still be quiescent after second cleanup")
        XCTAssertEqual(player.currentTime, 0, "currentTime should remain 0")
    }

    // AI:
    //   what: cleanup on a fresh (never-loaded) player is a no-op
    //   why:  PRD #31 — the view calls cleanup from onDisappear regardless of whether the user
    //         actually started playback. A fresh AudioPlayer that never loaded an AVAudioPlayer
    //         must survive cleanup() cleanly (no AVFoundation state to release, no timer to
    //         invalidate). This guards the nil-default path on `player`.
    //   ref:  PRD 31-audio-player-cleanup.json
    @MainActor
    func testCleanup_onFreshPlayer_isNoOp() {
        let player = AudioPlayer()

        player.cleanup()

        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertEqual(player.duration, 0)
    }
}
