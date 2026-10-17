// Trình phát Video toàn màn hình chuẩn iOS (AVKit + AVFoundation).
// Tự động kiểm tra bộ nhớ đệm iPhone (MediaDiskCache) để phát tức thì 0ms.
// Nếu video chưa lưu thì tải ngầm về đĩa rồi phát để tua mượt, không giật lag.
// Cấu hình âm thanh playback để phát tiếng chuẩn kể cả khi iPhone bật nút gạt im lặng.

import SwiftUI
import AVKit
import AVFoundation

struct VideoXemToan: Identifiable, Equatable {
    let url: URL
    let msgId: String
    var id: String { msgId }
}

struct TrinhPhatVideoView: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var player: AVPlayer?
    @State private var dangTai = true
    @State private var loi: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }

            if dangTai {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.3)
                    Text("Đang tải video…")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            if let loi {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text(loi)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            // Thanh công cụ trên
            VStack {
                HStack {
                    Spacer()
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.white.opacity(0.2), in: Circle())
                    }
                    Button {
                        player?.pause()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.white.opacity(0.2), in: Circle())
                    }
                }
                .padding()
                Spacer()
            }
        }
        .onAppear {
            khoiTaoPhat()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private func khoiTaoPhat() {
        // Cấu hình âm thanh playback để luôn phát tiếng kể cả khi iPhone bật nút gạt im lặng (Silent mode)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        // 1. Nếu video đã có trong bộ nhớ iPhone (MediaDiskCache) -> Phát ngay lập tức 0ms!
        if let cucBo = MediaDiskCache.shared.layFileCucBo(cho: url) {
            dangTai = false
            batDauPhat(fileUrl: cucBo)
            return
        }

        // 2. Nếu chưa có trên máy, tải về đĩa rồi phát để đảm bảo 100% không giật, tua mượt
        dangTai = true
        Task {
            if let cucBo = await MediaDiskCache.shared.taiVaLuuVideo(tu: url) {
                await MainActor.run {
                    self.dangTai = false
                    self.batDauPhat(fileUrl: cucBo)
                }
            } else {
                // Thử phát trực tiếp qua URL mạng nếu tải file gặp lỗi
                await MainActor.run {
                    self.dangTai = false
                    self.batDauPhat(fileUrl: url)
                }
            }
        }
    }

    private func batDauPhat(fileUrl: URL) {
        let item = AVPlayerItem(url: fileUrl)
        let p = AVPlayer(playerItem: item)
        self.player = p
        p.play()
    }
}
