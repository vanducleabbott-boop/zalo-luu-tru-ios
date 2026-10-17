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
                let thoiGianKhung = Double(ms ?? 100) / 1000
                TimelineView(.periodic(from: .zalo1970, by: 1.0 / 30)) { context in
                    let giayTron = context.date.timeIntervalSince(.zalo1970)
                    let idx = Int(giayTron / thoiGianKhung) % khung
                    AsyncImage(url: url) { pha in
                        switch pha {
                        case .success(let img):
                            img.resizable()
                                .frame(width: oCanh * CGFloat(khung), height: oCanh)
                                .offset(x: -CGFloat(idx) * oCanh)
                        default:
                            ProgressView()
                        }
                    }
                }
                .frame(width: oCanh, height: oCanh)
                .clipped()
            } else {
                AnimatedImageView(url: url, contentMode: .scaleAspectFit, boGoc: 0)
                    .frame(width: oCanh, height: oCanh)
            }
        } else {
            Text("[Sticker]").foregroundStyle(.secondary)
        }
    }
}
private extension Date { static let zalo1970 = Date(timeIntervalSince1970: 0) }

// ---------------------------------------------------------------- video
struct VideoTinView: View {
    let url: URL?
    // Giữ AVPlayer trong @State (không tạo mới mỗi lần body chạy lại) để video khỏi bị chạy lại từ đầu
    // mỗi khi màn chat vẽ lại (vd: có tin khác vừa cập nhật cảm xúc).
    @State private var player: AVPlayer?

    var body: some View {
        if let url {
            VideoPlayer(player: player)
                .frame(width: 260, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onAppear {
                    if player == nil {
                        if let cucBo = MediaDiskCache.shared.layFileCucBo(cho: url) {
                            player = AVPlayer(url: cucBo)
                        } else {
                            player = AVPlayer(url: url)
                            Task.detached(priority: .background) {
                                _ = await MediaDiskCache.shared.taiVaLuuVideo(tu: url)
                            }
                        }
                    }
                }
        } else {
            Text("Đang tải video về máy chủ…").font(.footnote).foregroundStyle(.secondary)
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

    @State private var dangTai = false
    @State private var fileCucBo: URL?
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
                    if dangTai { Text("Đang tải…").font(.caption).foregroundStyle(.secondary) }
                    else { Text(DinhDang.kichCo(kichThuoc)).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
                if dangTai { ProgressView() }
            }
            .frame(minWidth: 220, maxWidth: 300)
        }
        .buttonStyle(.plain)
        .disabled(url == nil || dangTai)
        .quickLookPreview($fileCucBo)
        .alert("Không tải được file", isPresented: Binding(get: { loi != nil }, set: { if !$0 { loi = nil } })) {
            Button("Đóng", role: .cancel) {}
        } message: { Text(loi ?? "") }
    }

    private func taiVeVaXem() async {
        guard let url else { return }
        if fileCucBo != nil { return }   // da tai xong tu lan truoc (vien quickLookPreview da tu mo khi tai xong)
        dangTai = true
        defer { dangTai = false }
        do {
            let (tam, _) = try await URLSession.shared.download(from: url)
            let dich = FileManager.default.temporaryDirectory.appendingPathComponent(tenFile ?? UUID().uuidString)
            try? FileManager.default.removeItem(at: dich)
            try FileManager.default.moveItem(at: tam, to: dich)
            fileCucBo = dich
        } catch { loi = error.localizedDescription }
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
