import AVFoundation
import Foundation

@MainActor
enum CatharsiaRefreshChime {
    private static var player: AVAudioPlayer?

    static func play() {
        guard let soundURL = Bundle.main.url(forResource: "CatharsiaRefresh", withExtension: "wav") else { return }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
            player = try AVAudioPlayer(contentsOf: soundURL)
            player?.volume = 0.42
            player?.prepareToPlay()
            player?.play()
        } catch {
            // Refresh still completes when audio is unavailable.
        }
    }
}
