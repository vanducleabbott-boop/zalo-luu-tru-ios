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
                nutTraLoiNho
                Spacer(minLength: 30)
            }

            VStack(alignment: t.laToi ? .trailing : .leading, spacing: 2) {
                if !t.laToi && laNhom && dauNhom {
                    Text(tenGui).font(.caption).foregroundStyle(ZaloMau.chuPhu).padding(.horizontal, 4)
                }
                bongBong
                    .contextMenu { menu }
                if t.camXuc.isEmpty == false {
                    HangCamXuc(camXuc: t.camXuc, uidToi: env.uidToi)
                }
            }
            if !t.laToi {
                nutTraLoiNho
                Spacer(minLength: 30)
            }
        }
        .padding(.top, dauNhom ? 8 : 1)
    }

    @ViewBuilder
    private var nutTraLoiNho: some View {
        if !t.thuHoi {
            Button {
                vm.chonTraLoi(t)
            } label: {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(width: 26, height: 26)
                    .background(Color(.systemGray5).opacity(0.8), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Trả lời")
            .padding(.bottom, 2)
        }
    }

    @ViewBuilder
    private var bongBong: some View {
        VStack(alignment: .leading, spacing: 4) {
            if t.thuHoi {
                Text(t.laToi ? "↩ Bạn đã thu hồi tin này" : "↩ Tin đã bị thu hồi")
                    .font(.caption.italic()).foregroundStyle(ZaloMau.mauDo)
            } else {
                if let q = t.quote { TrichDanXemTruoc(q: q).onTapGesture { chamTrichDan(q.msgId ?? "") } }
                noiDung
                if cuoiNhom && !trongSuot { Text(DinhDang.gioPhut(t.ts)).font(.caption2).foregroundStyle(ZaloMau.chuPhu) }
            }
        }
        .padding(trongSuot ? 0 : 10)
        .background(trongSuot ? AnyView(Color.clear) : AnyView(RoundedRectangle(cornerRadius: 12).fill(t.laToi ? ZaloMau.bongToi : ZaloMau.bongHo)))
    }

    private var trongSuot: Bool {
        t.kieu == "sticker" || (["anh", "gif", "video"].contains(t.kieu) && (t.chu ?? "").isEmpty && t.quote == nil && !t.thuHoi && t.file != nil)
    }

    @ViewBuilder
    private var noiDung: some View {
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
                LichHenTinView(lich: l, onXoa: {
                    guard let id = l.id else { return }
                    Task { await vm.xoaLichHen(id: id, cuocId: l.cuocLich) }
                })
            } else { Text(t.chu ?? "") }
        default:
            VanBanTinView(chu: t.chu ?? "", tags: t.phu?.tag)
        }
    }

    @ViewBuilder
    private var chuThichNeuCo: some View {
        if let c = t.chu, !c.isEmpty { VanBanTinView(chu: c, tags: t.phu?.tag).padding(.top, 2) }
    }

    private var diaChiFile: URL? { t.file.flatMap { env.api.diaChiMedia($0) } }

    @ViewBuilder
    private var menu: some View {
        Button { vm.chonTraLoi(t) } label: { Label("Trả lời", systemImage: "arrowshape.turn.up.left") }
        if t.kieu == "video", let u = diaChiFile {
            Button { videoDangXem = VideoXemToan(url: u, msgId: t.msgId) } label: { Label("Xem video", systemImage: "play.fill") }
        }
        if t.duocChuyenTiep {
            Button { chonChuyenTiep?(t) } label: { Label("Chuyển tiếp", systemImage: "arrowshape.turn.up.right") }
        }
        if let c = t.chu, !c.isEmpty {
            Button { UIPasteboard.general.string = c } label: { Label("Sao chép", systemImage: "doc.on.doc") }
        }
        if t.duocThaCamXuc {
            Menu("Thả cảm xúc") {
                ForEach(["/-heart", "/-strong", ":>", ":o", ":-((", ":-h"], id: \.self) { icon in
                    Button(BangCamXuc.emoji(icon)) { Task { await vm.thaCamXuc(t, icon: icon) } }
                }
            }
        }
        if t.duocThuHoi {
            Button(role: .destructive) { Task { await vm.thuHoi(t) } } label: { Label("Thu hồi", systemImage: "arrow.uturn.backward") }
        }
    }
}

struct AnhXemToan: Identifiable, Equatable { let url: URL; let msgId: String; var id: String { msgId } }

enum BangCamXuc {
    static let bang: [String: String] = ["/-heart": "❤️", "/-strong": "👍", ":>": "😆", ":o": "😮", ":-((": "😭", ":-h": "😡",
        ":-*": "😘", ":')": "😂", "/-shit": "💩", "/-rose": "🌹", "/-break": "💔", "/-weak": "👎", ";xx": "😍", ";-/": "😕",
        ";-)": "😉", "/-fade": "😶", "/-li": "☀️", "/-bd": "🎂", "/-bome": "💣", "/-ok": "👌"]
    static func emoji(_ icon: String) -> String { bang[icon] ?? "👍" }
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
