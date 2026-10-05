import Foundation
import AVFoundation
import Observation

// AI:
//   what: AudioPlayer observable wrapper for AVAudioPlayer playback
//   why:  PRD 09 requires play/pause, scrubber position, and timecode accessible
//         to SwiftUI views; @Observable + @MainActor keeps UI bindings on the main thread
//   ref:  specs/ui.md EntryDetailView, D-0003

@Observable
@MainActor
public final class AudioPlayer {

    private var player: AVAudioPlayer?

    public var isPlaying: Bool = false
    public var duration: Double = 0
    public var currentTime: Double = 0

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
    }

    public var timecode: String {
        let total = Int(currentTime)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public init() {}

    public func load(from url: URL) throws {
        stop()
        let p = try AVAudioPlayer(contentsOf: url)
        self.player = p
        self.duration = p.duration
        self.currentTime = 0
        self.isPlaying = false
    }

    public func play() {
        guard let player, !isPlaying else { return }
        player.prepareToPlay()
        if player.play() {
            isPlaying = true
            startTimer()
        }
    }

    public func pause() {
        guard let player, isPlaying else { return }
        player.pause()
        isPlaying = false
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    public func stop() {
        player?.stop()
        isPlaying = false
        currentTime = 0
        stopTimer()
    }

    public func scrub(to progress: Double) {
        guard let player else { return }
        let target = max(0, min(progress, 1.0)) * duration
        player.currentTime = target
        currentTime = target
    }

    private var timer: Timer?

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCurrentTime()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateCurrentTime() {
        guard let player else { return }
        currentTime = player.currentTime
        if !player.isPlaying {
            player.currentTime = 0
            currentTime = 0
            isPlaying = false
            stopTimer()
        }
    }

    // AI:
    //   what: cleanup — tears down the AVAudioPlayer instance and stops the polling timer
    //   why:  PRD #31 — EntryDetailView.onDisappear must hand off its audio session so that no
    //         AVAudioPlayer stays active after the user navigates away mid-playback. We route
    //         through `stop()` instead of re-implementing its logic so stop()'s timer/flag
    //         invariants always remain the source of truth — then release the player reference
    //         so the underlying AV resource is reclaimed. `stop()` is already idempotent (all
    //         guard/no-op paths are safe to re-enter), which means cleanup() itself is
    //         idempotent: calling it twice simply nils an already-nil player and re-stops a
    //         timer that's already stopped. Memory of duration/currentTime is intentionally
    //         left to `stop()` resetting currentTime to 0.
    //   ref:  PRD 31-audio-player-cleanup.json
    public func cleanup() {
        stop()
        player = nil
    }
}
