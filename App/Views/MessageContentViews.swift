// Nội dung bên trong 1 bong bóng tin, theo từng `kieu` - khớp noiDungTin() trong web/index.html.

import SwiftUI
import AVKit
import QuickLook

// ---------------------------------------------------------------- văn bản (có thể có "@Tag" + link)
struct VanBanTinView: View {
    let chu: String
    let tags: [TagMark]?
    var laTagToi = false

    var body: some View {
        Text(xayDung())
            .textSelection(.enabled)
    }

    private func xayDung() -> AttributedString {
        var ketQua = AttributedString()
        for (doan, laTag) in DinhDangChu.phanDoanTag(chu, tags: tags) {
            var a = thanLink(doan)
            if laTag { a.foregroundColor = ZaloMau.xanh; a.font = .body.weight(.medium) }
            ketQua += a
        }
        return ketQua
    }

    /// Gạch chân + bấm mở được các đoạn trông giống URL (khớp linkHoa() của web).
    private func thanLink(_ doan: String) -> AttributedString {
        var a = AttributedString(doan)
        guard let dd = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return a }
        let ns = doan as NSString
        for m in dd.matches(in: doan, range: NSRange(location: 0, length: ns.length)) {
            guard let url = m.url, let r = Range(m.range, in: a) else { continue }
            a[r].link = url
            a[r].foregroundColor = ZaloMau.xanh
        }
        return a
    }
}

// ---------------------------------------------------------------- ảnh / GIF
struct AnhTinView: View {
    let url: URL?
    var chamDeXem: (() -> Void)?

    var body: some View {
        if let url {
            AnimatedImageView(url: url, contentMode: .scaleAspectFit, boGoc: 10)
                .frame(maxWidth: 280, maxHeight: 340)
                .contentShape(Rectangle())
                .onTapGesture { chamDeXem?() }
        } else { khungDangTai }
    }
    private var khungDangTai: some View {
        Text("Đang tải về máy chủ…").font(.footnote).foregroundStyle(.secondary)
            .padding().frame(width: 180, height: 120).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
    private var khungLoi: some View {
        Image(systemName: "photo").foregroundStyle(.secondary)
            .frame(width: 180, height: 120).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

// ---------------------------------------------------------------- sticker (tĩnh hoặc sprite động / gif)
struct StickerTinView: View {
    let url: URL?
    let khung: Int?
    let ms: Int?
    private let oCanh: CGFloat = 112

    var body: some View {
        if let url {
            if let khung, khung > 1 {
                SpriteStickerView(url: url, khung: khung, ms: ms ?? 100, oCanh: oCanh)
            } else {
                AnimatedImageView(url: url, contentMode: .scaleAspectFit, boGoc: 0)
                    .frame(width: oCanh, height: oCanh)
            }
        } else {
            Text("[Sticker]").foregroundStyle(.secondary)
        }
    }
}

private struct SpriteStickerView: View {
    let url: URL
    let khung: Int
    let ms: Int
    let oCanh: CGFloat

    @State private var spriteImg: UIImage?

    var body: some View {
        Group {
            if let img = spriteImg {
                let thoiGianKhung = Double(ms) / 1000
                TimelineView(.periodic(from: .zalo1970, by: 1.0 / 30)) { context in
                    let giayTron = context.date.timeIntervalSince(.zalo1970)
                    let idx = Int(giayTron / thoiGianKhung) % max(1, khung)
                    Image(uiImage: img)
                        .resizable()
                        .frame(width: oCanh * CGFloat(khung), height: oCanh)
                        .offset(x: -CGFloat(idx) * oCanh)
                }
                .frame(width: oCanh, height: oCanh)
                .clipped()
            } else {
                ProgressView()
                    .frame(width: oCanh, height: oCanh)
                    .task {
                        await napSprite()
                    }
            }
        }
    }

    private func napSprite() async {
        let khoa = MediaDiskCache.shared.khoaCache(tu: url)
        if let cached = ImageCacheManager.shared.layAnh(khoa: khoa) {
            spriteImg = cached
            return
        }
        if let data = MediaDiskCache.shared.layDuLieu(cho: url), let img = UIImage(data: data) {
            ImageCacheManager.shared.luuAnh(img, khoa: khoa, dungLuong: data.count)
            spriteImg = img
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            MediaDiskCache.shared.luuDuLieu(data, cho: url)
            if let img = UIImage(data: data) {
                ImageCacheManager.shared.luuAnh(img, khoa: khoa, dungLuong: data.count)
                spriteImg = img
            }
        } catch {}
    }
}
private extension Date { static let zalo1970 = Date(timeIntervalSince1970: 0) }

// ---------------------------------------------------------------- video
struct VideoTinView: View {
    let url: URL?
    var chamDeXem: (() -> Void)? = nil

    @State private var anhBia: UIImage?
    @State private var daCoSan = false

    var body: some View {
        if let url {
            Button {
                chamDeXem?()
            } label: {
                ZStack {
                    if let img = anhBia {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 240, height: 180)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(width: 240, height: 180)
                            .overlay(
                                Image(systemName: "video.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.secondary)
                            )
                    }

                    // Nút Play tròn nổi bật
                    Circle()
                        .fill(.black.opacity(0.65))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white)
                                .offset(x: 2)
                        )

                    // Nhãn trạng thái góc dưới
                    HStack(spacing: 4) {
                        Image(systemName: "video")
                            .font(.caption2)
                        Text(daCoSan ? "Sẵn sàng" : "Video")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.6), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(8)
                }
                .frame(width: 240, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onAppear {
                kiemTraVaNapAnhBia()
            }
        } else {
            Text("Đang tải video về máy chủ…").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func kiemTraVaNapAnhBia() {
        guard let url else { return }
        if MediaDiskCache.shared.daCo(cho: url) {
            daCoSan = true
        }
        Task(priority: .background) {
            if let cucBo = MediaDiskCache.shared.layFileCucBo(cho: url) {
                if let thumb = await taoAnhThuNho(tu: cucBo) {
                    await MainActor.run { self.anhBia = thumb }
                }
            } else {
                // Tải trước ngầm
                _ = await MediaDiskCache.shared.taiVaLuuVideo(tu: url)
                if let cucBo = MediaDiskCache.shared.layFileCucBo(cho: url),
                   let thumb = await taoAnhThuNho(tu: cucBo) {
                    await MainActor.run {
                        self.daCoSan = true
                        self.anhBia = thumb
                    }
                }
            }
        }
    }

    private func taoAnhThuNho(tu fileUrl: URL) async -> UIImage? {
        let asset = AVURLAsset(url: fileUrl)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 360)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        return try? await withCheckedThrowingContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, result, error in
                if let image = image, result == .succeeded {
                    continuation.resume(returning: UIImage(cgImage: image))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// ---------------------------------------------------------------- ghi âm (voice message)
struct GhiAmTinView: View {
    let url: URL?
    @State private var player: AVPlayer?
    @State private var dangPhat = false

    var body: some View {
        HStack {
            Button {
                guard let url else { return }
                if player == nil { player = AVPlayer(url: url) }
                if dangPhat { player?.pause() } else { player?.play() }
                dangPhat.toggle()
            } label: {
                Image(systemName: dangPhat ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 30))
            }
            .disabled(url == nil)
            Text("Tin nhắn thoại").font(.footnote)
        }
        .foregroundStyle(url == nil ? .secondary : ZaloMau.xanh)
    }
}

// ---------------------------------------------------------------- file đính kèm (+ QuickLook/chia sẻ)
struct FileTinView: View {
    let url: URL?
    let tenFile: String?
    let kichThuoc: Int64?
    var chamDeXem: ((URL) -> Void)? = nil

    @State private var dangTai = false
    @State private var daCoSan = false
    @State private var loi: String?

    private var duoi: String { DinhDang.duoiFile(tenFile).uppercased() }
    private var mauBieu: Color {
        ["PDF": Color.red, "DOC": .blue, "DOCX": .blue, "XLS": .green, "XLSX": .green, "CSV": .green,
         "PPT": .orange, "PPTX": .orange, "ZIP": .brown, "RAR": .brown][duoi] ?? ZaloMau.chuPhu
    }

    var body: some View {
        Button { Task { await taiVeVaXem() } } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6).fill(mauBieu).frame(width: 40, height: 48)
                    .overlay(Text(duoi.isEmpty ? "FILE" : String(duoi.prefix(4))).font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tenFile ?? "Tệp").font(.system(size: 14, weight: .medium)).lineLimit(2)
                    if dangTai {
                        Text("Đang tải…").font(.caption).foregroundStyle(.secondary)
                    } else if daCoSan {
                        Text("\(DinhDang.kichCo(kichThuoc)) · Đã lưu trên iPhone").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(DinhDang.kichCo(kichThuoc)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if dangTai {
                    ProgressView()
                } else if daCoSan {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(ZaloMau.xanh)
                }
            }
            .frame(minWidth: 220, maxWidth: 300)
        }
        .buttonStyle(.plain)
        .disabled(url == nil || dangTai)
        .onAppear {
            kiemTraFileSanCo()
        }
        .alert("Không tải được file", isPresented: Binding(get: { loi != nil }, set: { if !$0 { loi = nil } })) {
            Button("Đóng", role: .cancel) {}
        } message: { Text(loi ?? "") }
    }

    private func kiemTraFileSanCo() {
        guard let url else { return }
        if MediaDiskCache.shared.daCo(cho: url, tenFile: tenFile) {
            daCoSan = true
        }
    }

    private func taiVeVaXem() async {
        guard let url else { return }
        if let cucBo = MediaDiskCache.shared.layFileCucBo(cho: url, tenFile: tenFile) {
            daCoSan = true
            chamDeXem?(cucBo)
            return
        }
        dangTai = true
        defer { dangTai = false }
        if let luu = await MediaDiskCache.shared.taiVaLuuFile(tu: url, tenFile: tenFile) {
            daCoSan = true
            chamDeXem?(luu)
        } else {
            loi = "Không thể tải tệp tin từ máy chủ. Vui lòng kiểm tra lại kết nối mạng."
        }
    }
}

// ---------------------------------------------------------------- lịch hẹn
struct LichHenTinView: View {
    let lich: LichHen

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Text(lich.emoji ?? "⏰").font(.system(size: 26))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(lich.tieuDe ?? "").font(.system(size: 14, weight: .semibold))
                        Text(lich.rieng == true ? "🔒 Riêng" : "Zalo").font(.system(size: 10))
                            .padding(.horizontal, 5).padding(.vertical, 1).background(.quaternary, in: Capsule())
                    }
                    Text(lich.daXoa == true ? "Đã xoá" : thoiGian)
                        .font(.caption).foregroundStyle(lich.daXoa == true ? .secondary : .primary)
                        .strikethrough(lich.daXoa == true)
                }
            }
        }
        .frame(minWidth: 220, maxWidth: 300, alignment: .leading)
    }

    private var thoiGian: String {
        guard let bd = lich.batDau else { return "" }
        return DinhDang.gioPhut(bd) + " · " + DinhDang.ngayDai(bd)
    }
}
