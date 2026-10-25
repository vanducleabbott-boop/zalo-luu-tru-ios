// 1 hàng tin nhắn trong khung chat - khớp đoạn render trong veTin() của web/index.html.

import SwiftUI

struct MessageBubble: View {
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject var vm: ChatViewModel
    let t: Tin
    let dauNhom: Bool
    let cuoiNhom: Bool
    let laNhom: Bool
    var chamTrichDan: (String) -> Void = { _ in }
    var chonChuyenTiep: ((Tin) -> Void)? = nil
    @Binding var anhDangXem: AnhXemToan?
    @Binding var videoDangXem: VideoXemToan?
    @Binding var fileDangXem: URL?
    /// v4.3: >1 tin = 1 album (nhiều ảnh/video gửi 1 lần) -> vẽ 1 khung lưới như Zalo; `t` là tin đầu album.
    var album: [Tin] = []

    private var tenGui: String {
        t.laToi ? "Bạn" : env.tenNguoi(uid: t.uid, macDinh: t.tenNguoi)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !t.laToi {
                if cuoiNhom {
                    AvatarView(ten: tenGui, anh: env.anhNguoi(uid: t.uid), khoa: t.uid ?? tenGui, kichThuoc: 28)
                } else {
                    Color.clear.frame(width: 28, height: 28)
                }
            } else {
                // 19/10/2026 (v4.1): bỏ nút trả lời nhỏ cạnh MỌI tin - trả lời bằng ẤN GIỮ tin -> "Trả lời" (menu)
                Spacer(minLength: 30)
            }

            VStack(alignment: t.laToi ? .trailing : .leading, spacing: 2) {
                if !t.laToi && laNhom && dauNhom {
                    Text(tenGui).font(.caption).foregroundStyle(ZaloMau.chuPhu).padding(.horizontal, 4)
                }
                bongBong
                    .contextMenu { menu }
                    .menuOrder(.fixed)
                if t.camXuc.isEmpty == false {
                    HangCamXuc(camXuc: t.camXuc, uidToi: env.uidToi)
                }
            }
            if !t.laToi {
                Spacer(minLength: 30)
            }
        }
        .padding(.top, dauNhom ? 8 : 1)
    }

    private var laTagToi: Bool {
        guard !t.laToi, let tag = t.phu?.tag, !tag.isEmpty else { return false }
        let toi = env.uidToi
        return tag.contains { $0.uid == toi || $0.uid == "-1" }
    }

    @ViewBuilder
    private var bongBong: some View {
        VStack(alignment: .leading, spacing: 4) {
            if laTagToi {
                HStack(spacing: 3) {
                    Image(systemName: "at")
                        .font(.system(size: 10, weight: .bold))
                    Text(t.phu?.tag?.contains(where: { $0.uid == "-1" }) == true ? "Nhắc đến cả nhóm" : "Nhắc đến bạn")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.12), in: Capsule())
                .padding(.bottom, 2)
            }
            if t.thuHoi {
                if env.hienTinThuHoi && coNoiDungLuu {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(t.laToi ? "Bạn đã thu hồi tin này (bản lưu)" : "Tin đã bị thu hồi (bản lưu)")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.12), in: Capsule())
                    .padding(.bottom, 2)

                    if let q = t.quote {
                        TrichDanXemTruoc(q: q)
                            .onTapGesture { chamTrichDan(q.msgId ?? "") }
                    }
                    noiDung
                    if cuoiNhom && !trongSuot {
                        HStack(spacing: 4) {
                            Text(DinhDang.gioPhut(t.ts))
                                .font(.caption2)
                                .foregroundStyle(ZaloMau.chuPhu)
                            Text("• Đã thu hồi")
                                .font(.caption2.italic())
                                .foregroundStyle(Color.red.opacity(0.85))
                        }
                    }
                } else {
                    Text(t.laToi ? "↩ Bạn đã thu hồi tin này" : "↩ Tin đã bị thu hồi")
                        .font(.caption.italic()).foregroundStyle(ZaloMau.mauDo)
                }
            } else {
                if let q = t.quote { TrichDanXemTruoc(q: q).onTapGesture { chamTrichDan(q.msgId ?? "") } }
                noiDung
                if cuoiNhom && !trongSuot { Text(DinhDang.gioPhut(t.ts)).font(.caption2).foregroundStyle(ZaloMau.chuPhu) }
            }
        }
        .padding(trongSuot ? 0 : 10)
        .background(
            trongSuot
                ? AnyView(Color.clear)
                : AnyView(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(t.laToi ? ZaloMau.bongToi : (laTagToi ? Color.orange.opacity(0.08) : ZaloMau.bongHo))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(vm.tinDuocNhayToi == t.msgId ? Color.orange : (t.thuHoi ? Color.red.opacity(0.35) : (laTagToi ? Color.orange.opacity(0.45) : Color.clear)), lineWidth: vm.tinDuocNhayToi == t.msgId ? 2.5 : 1)
                        )
                )
        )
    }

    private var coNoiDungLuu: Bool {
        !(t.chu ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || t.file != nil || t.quote != nil
    }

    private var trongSuot: Bool {
        album.count > 1 || !t.thuHoi && (t.kieu == "sticker" || (["anh", "gif", "video"].contains(t.kieu) && (t.chu ?? "").isEmpty && t.quote == nil && t.file != nil))
    }

    @ViewBuilder
    private var noiDung: some View {
        if album.count > 1 {
            AlbumLuoiView(ds: album, diaChi: { diaChiCua($0) },
                          chamAnh: { tin, u in anhDangXem = AnhXemToan(url: u, msgId: tin.msgId) },
                          chamVideo: { tin, u in videoDangXem = VideoXemToan(url: u, msgId: tin.msgId) })
        } else {
            noiDungDon
        }
    }

    @ViewBuilder
    private var noiDungDon: some View {
        if let db = t.loaiDacBiet {
            TinDacBietView(loai: db, ts: t.ts)
        } else {
            noiDungTheoKieu
        }
    }

    @ViewBuilder
    private var noiDungTheoKieu: some View {
        switch t.kieu {
        case "anh", "gif":
            AnhTinView(url: diaChiFile) { if let u = diaChiFile { anhDangXem = AnhXemToan(url: u, msgId: t.msgId) } }
            chuThichNeuCo
        case "sticker":
            StickerTinView(url: diaChiFile, khung: t.phu?.khung, ms: t.phu?.ms)
        case "video":
            VideoTinView(url: diaChiFile) {
                if let u = diaChiFile { videoDangXem = VideoXemToan(url: u, msgId: t.msgId) }
            }
            chuThichNeuCo
        case "ghiam":
            GhiAmTinView(url: diaChiFile)
        case "file":
            FileTinView(url: diaChiFile, tenFile: t.tenFile, kichThuoc: t.kichThuoc) { localURL in
                fileDangXem = localURL
            }
            chuThichNeuCo
        case "lich":
            if let l = t.phu?.lich {
                LichHenTinView(lich: l, cuocHienTaiId: vm.cuoc.id, onXoa: {
                    guard let id = l.id else { return }
                    Task { await vm.xoaLichHen(id: id, cuocId: l.cuocLich) }
                })
            } else { Text(t.chu ?? "") }
        case "danh-thiep":
            if let dt = t.phu?.danhThiep {
                DanhThiepTinView(dt: dt)
            } else {
                Text(t.chu ?? "")
            }
        case "binh-chon":
            if let bc = t.thongTinBinhChon {
                BinhChonTinView(vm: vm, bc: bc)
            } else {
                Text(t.chu ?? "")
            }
        default:
            if let ck = t.thongTinChuyenKhoan {
                // giữ nguyên chữ gốc phía trên thẻ (thẻ chỉ là phần nhận diện thêm, không được làm mất nội dung tin)
                VStack(alignment: .leading, spacing: 6) {
                    if let c = t.chu, !c.isEmpty { VanBanTinView(chu: c, tags: t.phu?.tag, laTagToi: laTagToi) }
                    ChuyenKhoanTinView(ck: ck)
                }
            } else if let bc = t.thongTinBinhChon {
                BinhChonTinView(vm: vm, bc: bc)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    VanBanTinView(chu: t.chu ?? "", tags: t.phu?.tag, laTagToi: laTagToi)
                    nhayVeCuocNguonNeuCo
                }
            }
        }
    }

    @ViewBuilder
    private var nhayVeCuocNguonNeuCo: some View {
        if let nguon = t.phu?.cuocNguon, !nguon.isEmpty, nguon != vm.cuoc.id {
            Button {
                env.moCuocHoiThoai(cuocId: nguon)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 11))
                    Text("Tới cuộc trò chuyện gốc")
                        .font(.caption2.weight(.medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(ZaloMau.xanh)
                .padding(.top, 2)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var chuThichNeuCo: some View {
        if let c = t.chu, !c.isEmpty { VanBanTinView(chu: c, tags: t.phu?.tag, laTagToi: laTagToi).padding(.top, 2) }
    }

    private var diaChiFile: URL? { diaChiCua(t) }

    private func diaChiCua(_ t: Tin) -> URL? {
        guard let f = t.file else { return nil }
        if f.hasPrefix("file://") {
            return URL(string: f)
        }
        if f.hasPrefix("/") {
            return URL(fileURLWithPath: f)
        }
        return env.api.diaChiMedia(f)
    }

    @ViewBuilder
    private var menu: some View {
        Button { vm.chonTraLoi(t) } label: { Label("Trả lời", systemImage: "arrowshape.turn.up.left") }
        Button {
            Task { await vm.chuyenTrangThaiGhim(t) }
        } label: {
            Label(vm.laTinGhim(t.msgId) ? "Bỏ ghim tin nhắn" : "Ghim tin nhắn",
                  systemImage: vm.laTinGhim(t.msgId) ? "pin.slash" : "pin")
        }
        if t.kieu == "video", let u = diaChiFile {
            Button { videoDangXem = VideoXemToan(url: u, msgId: t.msgId) } label: { Label("Xem video", systemImage: "play.fill") }
        }
        if t.duocChuyenTiep {
            Button { chonChuyenTiep?(t) } label: { Label("Chuyển tiếp", systemImage: "arrowshape.turn.up.right") }
        }
        if let c = t.chu, !c.isEmpty {
            Button { UIPasteboard.general.string = c } label: { Label("Sao chép", systemImage: "doc.on.doc") }
        }
        if t.duocThuHoi {
            Button(role: .destructive) { Task { await vm.thuHoi(t) } } label: { Label("Thu hồi", systemImage: "arrow.uturn.backward") }
        }
        if t.duocThaCamXuc {
            if #available(iOS 17.0, *) {
                Section {
                    ControlGroup {
                        ForEach(["/-heart", "/-strong", ":>", ":o", ":-((", ":-h"], id: \.self) { icon in
                            Button { Task { await vm.thaCamXuc(t, icon: icon) } } label: {
                                Image(uiImage: BangCamXuc.anh(BangCamXuc.emoji(icon))).renderingMode(.original)
                            }
                        }
                    } label: { Text("Thả cảm xúc") }
                    .controlGroupStyle(.palette)
                }
            } else {
                Menu("Thả cảm xúc") {
                    ForEach(["/-heart", "/-strong", ":>", ":o", ":-((", ":-h"], id: \.self) { icon in
                        Button(BangCamXuc.emoji(icon)) { Task { await vm.thaCamXuc(t, icon: icon) } }
                    }
                }
            }
        }
    }
}

struct AnhXemToan: Identifiable, Equatable { let url: URL; let msgId: String; var id: String { msgId } }

enum BangCamXuc {
    static let bang: [String: String] = ["/-heart": "❤️", "/-strong": "👍", ":>": "😆", ":o": "😮", ":-((": "😭", ":-h": "😡",
        ":-*": "😘", ":')": "😂", "/-shit": "💩", "/-rose": "🌹", "/-break": "💔", "/-weak": "👎", ";xx": "😍", ";-/": "😕",
        ";-)": "😉", "/-fade": "😶", "/-li": "☀️", "/-bd": "🎂", "/-bome": "💣", "/-ok": "👌"]
    static func emoji(_ icon: String) -> String { bang[icon] ?? "👍" }
    static func anh(_ emoji: String) -> UIImage {
        let kichThuoc = CGSize(width: 30, height: 30)
        let r = UIGraphicsImageRenderer(size: kichThuoc)
        return r.image { _ in
            let s = NSAttributedString(string: emoji, attributes: [.font: UIFont.systemFont(ofSize: 26)])
            let c = s.size()
            s.draw(at: CGPoint(x: (kichThuoc.width - c.width) / 2, y: (kichThuoc.height - c.height) / 2))
        }
    }
}

struct HangCamXuc: View {
    let camXuc: [CamXucTin]
    let uidToi: String
    var body: some View {
        let dem = Dictionary(grouping: camXuc, by: \.icon).mapValues(\.count)
        let top = dem.keys.sorted { (dem[$0] ?? 0) > (dem[$1] ?? 0) }.prefix(3)
        HStack(spacing: 1) {
            ForEach(Array(top), id: \.self) { Text(BangCamXuc.emoji($0)).font(.system(size: 11)) }
            if camXuc.count > 1 { Text("\(camXuc.count)").font(.system(size: 10)).foregroundStyle(ZaloMau.chuPhu) }
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(ZaloMau.bongHo, in: Capsule())
        .shadow(radius: 1)
    }
}

struct TrichDanXemTruoc: View {
    let q: TrichDan
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(q.ten ?? "").font(.caption.bold())
            Text((q.chu?.isEmpty ?? true) ? "Tin nhắn" : q.chu!).font(.caption).foregroundStyle(ZaloMau.chuPhu).lineLimit(2)
        }
        .padding(6)
        .background(ZaloMau.xanh.opacity(0.08))
        .overlay(Rectangle().fill(ZaloMau.xanh).frame(width: 2), alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
