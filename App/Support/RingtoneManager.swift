import Foundation
import AVFoundation
import AudioToolbox
import UIKit

@MainActor
final class RingtoneManager: NSObject, AVAudioPlayerDelegate {
    static let shared = RingtoneManager()

    private var player: AVAudioPlayer?
    private var rungTimer: Timer?
    private(set) var dangDoChuong = false

    private override init() {
        super.init()
    }

    func batDauChuong() {
        guard !dangDoChuong else { return }
        dangDoChuong = true

        // 1. Cấu hình AudioSession để phát nhạc chuông to rõ
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("[Ringtone] Loi cau hinh AVAudioSession:", error.localizedDescription)
        }

        // 2. Nạp và phát file ringtone.wav lặp liên tục
        let soundURL = Bundle.main.url(forResource: "ringtone", withExtension: "wav")
            ?? Bundle.main.url(forResource: "ringtone", withExtension: "wav", subdirectory: "Resources")

        if let soundURL {
            do {
                let p = try AVAudioPlayer(contentsOf: soundURL)
                p.delegate = self
                p.numberOfLoops = -1 // Lặp vô tận cho tới khi bốc máy hoặc cúp máy
                p.volume = 1.0
                p.prepareToPlay()
                p.play()
                self.player = p
                print("[Ringtone] Da bat dau do chuong cuoc goi den!")
            } catch {
                print("[Ringtone] Loi phat file chuong:", error.localizedDescription)
            }
        } else {
            print("[Ringtone] Khong tim thay file ringtone.wav trong bundle!")
        }

        // 3. Rung lặp liên tục mỗi 1.5 giây
        kichHoatRung()
        rungTimer?.invalidate()
        rungTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.kichHoatRung()
            }
        }
    }

    func tatChuong() {
        guard dangDoChuong else { return }
        dangDoChuong = false

        player?.stop()
        player = nil

        rungTimer?.invalidate()
        rungTimer = nil

        print("[Ringtone] Da tat chuong cuoc goi")

        // Phục hồi lại luồng âm thanh tĩnh nền 24/7
        BackgroundAudioManager.shared.batDauChayNen()
    }

    private func kichHoatRung() {
        guard dangDoChuong else { return }
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        let feedback = UIImpactFeedbackGenerator(style: .heavy)
        feedback.impactOccurred()
    }
}
