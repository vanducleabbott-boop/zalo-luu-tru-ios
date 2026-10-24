// Nội dung bên trong 1 bong bóng tin, theo từng `kieu` - khớp noiDungTin() trong web/index.html.

import SwiftUI
import AVKit
import QuickLook

// ---------------------------------------------------------------- văn bản (có thể có "@Tag" + link)
struct VanBanTinView: View {
    @EnvironmentObject var env: AppEnvironment
    let chu: String
    let tags: [TagMark]?
    var laTagToi = false

    /// v5.9: bấm "@Tên" -> mở chat riêng với người đó (chat 1-1 trên Zalo có mã cuộc = uid người đó).
    static let luocDoTag = "zlt-tag"

    var body: some View {
        Text(xayDung())
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == Self.luocDoTag, let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let uid = c.host, !uid.isEmpty else { return .systemAction }
                let ten = c.queryItems?.first(where: { $0.name == "ten" })?.value
                env.moCuocHoiThoai(cuocId: uid, tenCuoc: env.dsCuocCache[uid]?.ten ?? ten)
                return .handled
            })
    }

    private func xayDung() -> AttributedString {
        var ketQua = AttributedString()
        for (doan, uid) in DinhDangChu.phanDoanTagUid(chu, tags: tags) {
            var a = thanLink(doan)
            if let uid {
                a.foregroundColor = ZaloMau.xanh; a.font = .body.weight(.medium)
                // "@Tất cả" (-1) và tag chính mình thì không có chat riêng để mở
                if uid != "-1", uid != env.uidToi, let url = urlTag(uid, ten: doan) { a.link = url }
            }
            ketQua += a
        }
        return ketQua
    }

    private func urlTag(_ uid: String, ten: String) -> URL? {
        var c = URLComponents()
        c.scheme = Self.luocDoTag
        c.host = uid
        let tenSach = ten.hasPrefix("@") ? String(ten.dropFirst()) : ten
        c.queryItems = [URLQueryItem(name: "ten", value: tenSach)]
        return c.url
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

    @State private var kichThuocAnh: CGSize?

    var body: some View {
        if let url {
            Button {
                chamDeXem?()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))

                    AnimatedImageView(url: url, contentMode: .scaleAspectFill, boGoc: 12) { size in
                        self.kichThuocAnh = size
                    }
                }
                .frame(width: tinhChieuRong(), height: tinhChieuCao())
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        } else {
            khungChuaLuu
        }
    }

    private func tinhChieuRong() -> CGFloat {
        guard let size = kichThuocAnh, size.width > 0, size.height > 0 else { return 250 }
        if size.width >= size.height {
            // Ảnh ngang hoặc vuông: rộng 260pt
            return 260
        } else {
            // Ảnh dọc: rộng theo tỉ lệ nhưng không dưới 180pt và tối đa 240pt
            let tiLe = size.width / size.height
            return max(180, min(240, 300 * tiLe))
        }
    }

    private func tinhChieuCao() -> CGFloat {
        guard let size = kichThuocAnh, size.width > 0, size.height > 0 else { return 190 }
        let w = tinhChieuRong()
        let tiLe = size.height / size.width
        let h = w * tiLe
        // Chiều cao tối thiểu 150pt, tối đa 340pt
        return max(150, min(340, h))
    }

    private var khungChuaLuu: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("Ảnh chưa lưu trữ")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("File gốc đã hết hạn trên Zalo")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .frame(width: 220, height: 120)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
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
                // alignment .leading: dải sprite phải sát MÉP TRÁI ô rồi mới dịch. Để mặc định (giữa) thì sticker có số
                // khung CHẴN bị cắt đúng ranh giới 2 khung -> hiện 2 nửa mặt ghép nhau (lỗi 20/10/2026, v4.2).
                .frame(width: oCanh, height: oCanh, alignment: .leading)
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
            khungChuaLuu
        }
    }

    private var khungChuaLuu: some View {
        VStack(spacing: 6) {
            Image(systemName: "video.badge.exclamationmark")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("Video chưa lưu trữ")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("File gốc đã hết hạn trên Zalo")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .frame(width: 220, height: 120)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
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
    @State private var hienLoiChuaLuu = false

    private var tenHienThi: String { DinhDang.tenHienThiFile(tenFile) }
    private var duoi: String { DinhDang.duoiFile(tenFile).uppercased() }

    private var mauBieu: Color {
        switch duoi {
        case "PDF": return Color(red: 0.90, green: 0.20, blue: 0.20)
        case "DOC", "DOCX": return Color(red: 0.12, green: 0.45, blue: 0.90) // Word
        case "XLS", "XLSX", "CSV": return Color(red: 0.13, green: 0.65, blue: 0.35) // Excel
        case "PPT", "PPTX": return Color(red: 0.95, green: 0.42, blue: 0.12) // PowerPoint
        case "ZIP", "RAR", "7Z", "TAR": return Color(red: 0.60, green: 0.42, blue: 0.25)
        case "TXT", "RTF", "LOG": return Color(red: 0.45, green: 0.50, blue: 0.55)
        default: return ZaloMau.xanh
        }
    }

    private var iconBieuTuong: String {
        switch duoi {
        case "PDF": return "doc.text.fill"
        case "DOC", "DOCX": return "doc.richtext.fill"
        case "XLS", "XLSX", "CSV": return "tablecells.fill"
        case "PPT", "PPTX": return "rectangle.inset.filled.and.person.filled"
        case "ZIP", "RAR", "7Z": return "doc.zipper"
        default: return "doc.fill"
        }
    }

    var body: some View {
        Button {
            xuLyBam()
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(mauBieu)
                    .frame(width: 44, height: 50)
                    .overlay(
                        VStack(spacing: 2) {
                            Image(systemName: iconBieuTuong)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(duoi.isEmpty ? "FILE" : String(duoi.prefix(4)))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(tenHienThi).font(.system(size: 14, weight: .medium)).lineLimit(2)
                    if url == nil {
                        Text("\(DinhDang.kichCo(kichThuoc)) · Chưa lưu trên máy chủ").font(.caption).foregroundStyle(.secondary)
                    } else if dangTai {
                        Text("Đang tải…").font(.caption).foregroundStyle(.secondary)
                    } else if daCoSan {
                        Text("\(DinhDang.kichCo(kichThuoc)) · Đã lưu trên iPhone").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("\(DinhDang.kichCo(kichThuoc)) · Chạm để xem trước").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if dangTai {
                    ProgressView()
                } else if daCoSan {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(ZaloMau.xanh)
                } else if url != nil {
                    Image(systemName: "arrow.down.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 220, maxWidth: 300)
        }
        .buttonStyle(.plain)
        .disabled(dangTai)
        .onAppear {
            kiemTraFileSanCo()
        }
        .alert("Tệp tin chưa có trên máy chủ", isPresented: $hienLoiChuaLuu) {
            Button("Đóng", role: .cancel) {}
        } message: {
            Text("Tệp \"\(tenHienThi)\" chưa từng được tải về máy chủ lưu trữ (chỉ có thông tin tin nhắn từ Zalo). Bạn chỉ có thể xem các tệp đã được lưu trong kho.")
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

    private func xuLyBam() {
        guard url != nil else {
            hienLoiChuaLuu = true
            return
        }
        Task { await taiVeVaXem() }
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
    @EnvironmentObject var env: AppEnvironment
    let lich: LichHen
    var cuocHienTaiId: String? = nil
    var onXoa: (() -> Void)? = nil

    @State private var hienXacNhanXoa = false

    private var daQua: Bool {
        guard let bd = lich.batDau else { return false }
        return bd < Int64(Date().timeIntervalSince1970 * 1000)
    }

    private var chuLap: String? {
        switch lich.lap {
        case 1: return "Lặp hằng ngày"
        case 2: return "Lặp hằng tuần"
        case 3: return "Lặp hằng tháng"
        default: return nil
        }
    }

    private var coTheXoa: Bool {
        lich.daXoa != true && (lich.rieng == true || lich.cuaToi != false) && onXoa != nil
    }

    private var cuocMucTieuId: String? {
        if let nguon = lich.cuocNguon, !nguon.isEmpty, nguon != cuocHienTaiId {
            return nguon
        }
        if let cuocLich = lich.cuocLich, !cuocLich.isEmpty, cuocLich != "so-tay", cuocLich != "so_tay", cuocLich != cuocHienTaiId {
            return cuocLich
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Phần thẻ thông tin lịch hẹn: có thể nhấn để nhảy về cuộc trò chuyện gốc
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Text(lich.emoji ?? "⏰")
                        .font(.system(size: 28))
                        .frame(width: 38, height: 38)
                        .background(Color(.systemGray5), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(lich.tieuDe ?? "Lịch hẹn")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(lich.daXoa == true ? .secondary : .primary)
                                .strikethrough(lich.daXoa == true)
                                .lineLimit(2)

                            Spacer(minLength: 0)

                            Text(lich.rieng == true ? "🔒 Riêng" : "Zalo")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(lich.rieng == true ? .secondary : ZaloMau.xanh)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(lich.rieng == true ? Color(.systemGray5) : ZaloMau.xanhNhat, in: Capsule())
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 11))
                            Text(lich.daXoa == true ? "Đã xoá lịch" : thoiGian)
                                .font(.caption)
                        }
                        .foregroundStyle(lich.daXoa == true ? .secondary : (daQua ? .secondary : ZaloMau.xanh))
                        .strikethrough(lich.daXoa == true)

                        if let chuLap, lich.daXoa != true {
                            Text(chuLap)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if let tenCuoc = lich.tenCuoc, !tenCuoc.isEmpty {
                            Text("Từ: \(tenCuoc)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Nút / hiển thị nhảy tới cuộc trò chuyện
                if let mucTieu = cuocMucTieuId {
                    Divider()
                    Button {
                        env.moCuocHoiThoai(cuocId: mucTieu, tenCuoc: lich.tenCuoc, msgId: lich.msgNguon, quanhTs: lich.taoLuc)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 12))
                            Text(lich.tenCuoc.flatMap { !$0.isEmpty ? "Tới trò chuyện: \($0)" : nil } ?? "Tới cuộc trò chuyện")
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(ZaloMau.xanh)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let mucTieu = cuocMucTieuId {
                    env.moCuocHoiThoai(cuocId: mucTieu, tenCuoc: lich.tenCuoc, msgId: lich.msgNguon, quanhTs: lich.taoLuc)
                }
            }

            if coTheXoa {
                Divider()
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        hienXacNhanXoa = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                            Text("Xoá lịch hẹn")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .frame(minWidth: 230, maxWidth: 300, alignment: .leading)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
        .confirmationDialog("Xoá lịch hẹn \"\(lich.tieuDe ?? "")\"?", isPresented: $hienXacNhanXoa, titleVisibility: .visible) {
            Button("Xoá lịch hẹn", role: .destructive) {
                onXoa?()
            }
            Button("Huỷ", role: .cancel) {}
        }
    }

    private var thoiGian: String {
        guard let bd = lich.batDau else { return "" }
        return DinhDang.gioPhut(bd) + " · " + DinhDang.ngayDai(bd)
    }
}

// ---------------------------------------------------------------- Danh thiếp / Liên hệ
struct DanhThiepTinView: View {
    @EnvironmentObject var env: AppEnvironment
    let dt: DanhThiepInfo
    @State private var daSaoChep = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AvatarView(
                    ten: dt.ten ?? "Liên hệ",
                    anh: dt.avatar,
                    khoa: dt.uid ?? dt.ten ?? "",
                    kichThuoc: 46
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(dt.ten ?? "Liên hệ Zalo")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    if let sdt = dt.sdt, !sdt.isEmpty {
                        Text(sdt)
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    } else {
                        Text("Danh thiếp Zalo")
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if let sdt = dt.sdt, !sdt.isEmpty {
                Divider()
                HStack(spacing: 8) {
                    if let url = URL(string: "tel://\(sdt.filter { !" -()".contains($0) })"), UIApplication.shared.canOpenURL(url) {
                        Button {
                            UIApplication.shared.open(url)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 11))
                                Text("Gọi điện")
                                    .font(.caption.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(Color.blue)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        UIPasteboard.general.string = sdt
                        daSaoChep = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            daSaoChep = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: daSaoChep ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11))
                            Text(daSaoChep ? "Đã chép" : "Sao chép")
                                .font(.caption.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(daSaoChep ? Color.green : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .frame(minWidth: 230, maxWidth: 280, alignment: .leading)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }
}
