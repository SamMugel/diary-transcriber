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
final class AudioPlayer {

    private var player: AVAudioPlayer?

    var isPlaying: Bool = false
    var duration: Double = 0
    var currentTime: Double = 0

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
    }

    var timecode: String {
        let total = Int(currentTime)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func load(from url: URL) throws {
        stop()
        let p = try AVAudioPlayer(contentsOf: url)
        self.player = p
        self.duration = p.duration
        self.currentTime = 0
        self.isPlaying = false
    }

    func play() {
        guard let player, !isPlaying else { return }
        player.prepareToPlay()
        if player.play() {
            isPlaying = true
            startTimer()
        }
    }

    func pause() {
        guard let player, isPlaying else { return }
        player.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func stop() {
        player?.stop()
        isPlaying = false
        currentTime = 0
        stopTimer()
    }

    func scrub(to progress: Double) {
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

    func cleanup() {
        timer?.invalidate()
        timer = nil
    }
}
