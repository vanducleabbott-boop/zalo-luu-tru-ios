// Khung lưới ALBUM (v4.3, 20/10/2026): nhiều ảnh/video gửi 1 lần hiện chung 1 khung như Zalo gốc.
// Xếp hàng: 2 -> [2]; 3 -> [3]; 4 -> [2,2]; 5 -> [3,2]; 6 -> [3,3]; 7 -> [3,2,2]... (hàng 3 trước, đuôi thừa 1 thì
// đổi thành 2+2 để không có hàng 1 ảnh). Ô vuông, khe 2pt, bo góc cả khung. Chạm ảnh -> xem lớn, chạm video -> phát.

import SwiftUI
import AVFoundation

struct AlbumLuoiView: View {
    let ds: [Tin]
    let diaChi: (Tin) -> URL?
    let chamAnh: (Tin, URL) -> Void
    let chamVideo: (Tin, URL) -> Void
    var dangTai: (Tin) -> Bool = { _ in false }   // v7.8: ô đang tải lên máy chủ -> vòng xoay

    private let rong: CGFloat = 260
    private let khe: CGFloat = 2

    /// Số ô từng hàng.
    static func chiaHang(_ n: Int) -> [Int] {
        guard n > 0 else { return [] }
        if n == 1 { return [1] }
        if n == 2 { return [2] }
        if n == 4 { return [2, 2] }
        var hang: [Int] = []
        var con = n
        while con > 0 {
            if con == 4 { hang += [2, 2]; con = 0 }
            else if con == 2 { hang.append(2); con = 0 }
            else if con == 1 { hang.append(1); con = 0 }
            else { hang.append(3); con -= 3 }
        }
        return hang
    }

    var body: some View {
        let hang = Self.chiaHang(ds.count)
        VStack(spacing: khe) {
            ForEach(Array(hang.enumerated()), id: \.offset) { h, soO in
                let batDau = hang.prefix(h).reduce(0, +)
                let canh = (rong - khe * CGFloat(soO - 1)) / CGFloat(soO)
                HStack(spacing: khe) {
                    ForEach(batDau..<(batDau + soO), id: \.self) { i in
                        o(ds[i], canh: canh)
                    }
                }
            }
        }
        .frame(width: rong)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func o(_ t: Tin, canh: CGFloat) -> some View {
        if let u = diaChi(t) {
            Button {
                if t.kieu == "video" { chamVideo(t, u) } else { chamAnh(t, u) }
            } label: {
                ZStack {
                    Color(.systemGray5)
                    if t.kieu == "video" {
                        AnhBiaVideo(url: u)
                        Circle().fill(.black.opacity(0.6)).frame(width: 36, height: 36)
                            .overlay(Image(systemName: "play.fill").font(.system(size: 15)).foregroundStyle(.white).offset(x: 1))
                    } else {
                        AnimatedImageView(url: u, contentMode: .scaleAspectFill, boGoc: 0)
                    }
                }
                .frame(width: canh, height: canh)
                .clipped()
                .overlay {
                    if dangTai(t) {
                        ZStack {
                            Color.black.opacity(0.35)
                            ProgressView().tint(.white).controlSize(.regular)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Color(.systemGray5)
                .frame(width: canh, height: canh)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }
}

/// Ảnh bìa video trong ô album (khung đầu, tạo 1 lần, nhớ trong RAM theo URL).
private struct AnhBiaVideo: View {
    let url: URL
    @State private var anh: UIImage?
    private static var nho: [URL: UIImage] = [:]

    var body: some View {
        Group {
            if let anh { Image(uiImage: anh).resizable().scaledToFill() }
            else { Image(systemName: "video.fill").foregroundStyle(.secondary) }
        }
        .task(id: url) {
            if let c = Self.nho[url] { anh = c; return }
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 400, height: 400)
            if let cg = try? await gen.image(at: .zero).image {
                let ui = UIImage(cgImage: cg)
                Self.nho[url] = ui
                anh = ui
            }
        }
    }
}
