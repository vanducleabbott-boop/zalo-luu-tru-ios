// Giữ app không bị iOS đóng băng (suspend) khi người dùng chuyển sang app khác hoặc khoá màn hình.
// Kết hợp quyền UIBackgroundModes: [audio] trong Info.plist với luồng âm thanh tĩnh (silence) lặp vô tận,
// dùng cờ .mixWithOthers để hoàn toàn không ảnh hưởng tới âm thanh, nhạc hay cuộc gọi khác của máy.

import Foundation
import AVFoundation
import UIKit

final class BackgroundAudioManager {
    static let shared = BackgroundAudioManager()
    private var audioPlayer: AVAudioPlayer?
    private var daKhoiTao = false

    private init() {
        // 19/10/2026: cuộc gọi điện thoại thật / Siri / app khác làm iOS DỪNG tiếng tĩnh (interruption) mà trước đây
        // không ai phát lại -> app bị treo ở nền, SSE chết, không nhận chuông. Hết gián đoạn thì phát lại.
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended,
                  self?.dangGoi == false else { return }   // đang gọi: để trang Cuộc gọi tự lo âm thanh
            try? AVAudioSession.sharedInstance().setActive(true)
            self?.batDauChayNen()
        }
        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            self?.daKhoiTao = false
            self?.batDauChayNen()
        }
    }

    /// Đang trong cuộc gọi: KHÔNG được đụng AVAudioSession / phát tiếng tĩnh. Trang Cuộc gọi (WKWebView) dùng chung
    /// audio session của app - app phát/kích hoạt âm thanh giữa cuộc gọi làm iOS NGẮT mic + loa của trang
    /// (log 19/10/2026: "mic track MUTE" + "AudioContext -> interrupted" 2s sau khi bắt đầu). Giữ nền lúc gọi = vị trí.
    private(set) var dangGoi = false

    func batDauChayNen() {
        guard !dangGoi else { return }
        guard !daKhoiTao else {
            if let p = audioPlayer, !p.isPlaying {
                p.play()
            }
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let silentData = taoDuLieuWavYenLang()
            let player = try AVAudioPlayer(data: silentData)
            player.numberOfLoops = -1 // Lặp vô tận
            player.volume = 0.0
            player.prepareToPlay()
            player.play()

            self.audioPlayer = player
            self.daKhoiTao = true
            print("[BackgroundAudio] Da kich hoat luong am thanh tinh giu ket noi nen 24/7")
        } catch {
            print("[BackgroundAudio] Loi khoi tao am thanh nen:", error.localizedDescription)
        }
    }

    func dungChayNen() {
        audioPlayer?.stop()
        daKhoiTao = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Tạm dừng phát tiếng tĩnh để nhường trọn vẹn luồng AudioSession / Micro cho đàm thoại cuộc gọi
    func tamDungChoCuocGoi() {
        dangGoi = true
        audioPlayer?.pause()
    }

    /// Hết cuộc gọi (hoặc có cuộc gọi mới đến) -> phát lại tiếng tĩnh giữ nền.
    func tiepTucSauCuocGoi() {
        dangGoi = false
        batDauChayNen()
    }

    /// Tạo 1 giây file âm thanh WAV hoàn toàn tĩnh (im lặng - PCM số 0) trong bộ nhớ RAM (chỉ ~16KB)
    private func taoDuLieuWavYenLang() -> Data {
        let sampleRate: Int32 = 8000
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate: Int32 = sampleRate * Int32(numChannels) * Int32(bitsPerSample / 8)
        let blockAlign: Int16 = numChannels * (bitsPerSample / 8)
        let durationSeconds: Int = 1
        let numSamples: Int = Int(sampleRate) * durationSeconds
        let dataSize: Int32 = Int32(numSamples * Int(blockAlign))
        let chunkSize: Int32 = 36 + dataSize

        var data = Data()
        // RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        var chunkSizeBytes = chunkSize.littleEndian
        data.append(Data(bytes: &chunkSizeBytes, count: 4))
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        // fmt subchunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        var subchunk1Size: Int32 = Int32(16).littleEndian
        data.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: Int16 = Int16(1).littleEndian // PCM
        data.append(Data(bytes: &audioFormat, count: 2))
        var channels = numChannels.littleEndian
        data.append(Data(bytes: &channels, count: 2))
        var sRate = sampleRate.littleEndian
        data.append(Data(bytes: &sRate, count: 4))
        var bRate = byteRate.littleEndian
        data.append(Data(bytes: &bRate, count: 4))
        var bAlign = blockAlign.littleEndian
        data.append(Data(bytes: &bAlign, count: 2))
        var bps = bitsPerSample.littleEndian
        data.append(Data(bytes: &bps, count: 2))
        // data subchunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        var dSize = dataSize.littleEndian
        data.append(Data(bytes: &dSize, count: 4))
        // PCM silence (tất cả là byte 0)
        data.append(Data(repeating: 0, count: Int(dataSize)))
        return data
    }
}
