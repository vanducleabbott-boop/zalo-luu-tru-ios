// 1 cuộc trò chuyện đang mở: tải tin, cuộn lên tải tin cũ, gửi/thu hồi/thả cảm xúc, cập nhật realtime.
// Khớp moCuoc()/taiTinCu()/taiBu()/guiChu()/thaCamXuc() trong web/index.html.

import Foundation
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var cuoc: Cuoc
    @Published private(set) var tinDangXem: [Tin] = []
    @Published private(set) var heTin = false        // da toi tin cu nhat
    @Published private(set) var dangTaiTinCu = false
    @Published private(set) var dangTai = false
    @Published var daCuonXuongCuoiLanDau = false
    @Published var traLoi: Tin?
    @Published var loi: String?
    /// Khi khác nil: UI nên cuộn tới tin nhắn này 1 lần rồi tự xoá giá trị (xem onChange trong ChatView).
    @Published var cuonToiMsgId: String?

    let env: AppEnvironment
    private var cheDoQuanh = false
    private var huyTheoDoi = Set<AnyCancellable>()

    init(cuoc: Cuoc, env: AppEnvironment) {
        self.cuoc = cuoc
        self.env = env
        env.sse.suKien
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sk in self?.xuLySuKien(sk) }
            .store(in: &huyTheoDoi)
    }

    var danhSachHienThi: [GomNhom.MucHienThi] { GomNhom.gomTheoNgay(tinDangXem) }

    func taiLan1(quanh: Int64? = nil, sangMsgId: String? = nil) async {
        cheDoQuanh = quanh != nil

        // 1. Nếu có tin nhắn đã lưu trong bộ nhớ đệm, hiển thị ngay lập tức (0ms delay)
        var daCoCache = false
        if quanh == nil, let cached = TinNhanDiskCache.shared.layTin(cuocId: cuoc.id), !cached.isEmpty {
            tinDangXem = cached
            daCoCache = true
            Task { await napNguoiLienQuan(cached) }
            if let sangMsgId { cuonToiMsgId = sangMsgId } else { cuonToiMsgId = "__cuoi__" }
        }

        // 2. Tải làm mới từ máy chủ
        if !daCoCache { dangTai = true }
        defer { dangTai = false }
        do {
            let kq = try await env.api.dsTin(cuoc: cuoc.id, quanh: quanh)
            if let c = kq.cuoc { cuoc = c }
            if let toi = kq.toi, !toi.isEmpty { env.uidToi = toi }
            let cuCount = tinDangXem.count
            tinDangXem = kq.tin
            heTin = kq.tin.count < 60
            if quanh == nil {
                TinNhanDiskCache.shared.luuTin(kq.tin, cuocId: cuoc.id)
            }
            await napNguoiLienQuan(kq.tin)
            taiTruocMediaTheoQuyDinh(kq.tin)
            if let sangMsgId {
                cuonToiMsgId = sangMsgId
            } else if cuCount != kq.tin.count || !daCoCache {
                cuonToiMsgId = "__cuoi__"
            }
            if quanh == nil && cuoc.chuaDoc > 0 { danhDauDaDoc() }
        } catch {
            if tinDangXem.isEmpty { loi = error.localizedDescription }
        }
    }

    func taiTinCu() async {
        guard daCuonXuongCuoiLanDau, !heTin, !dangTaiTinCu, let dauTien = tinDangXem.first else { return }
        dangTaiTinCu = true
        defer { dangTaiTinCu = false }
        do {
            let kq = try await env.api.dsTin(cuoc: cuoc.id, truoc: dauTien.ts)
            let (ds, het) = PhanTrang.noiTrangCu(hienTai: tinDangXem, trangCu: kq.tin)
            tinDangXem = ds
            heTin = het
            TinNhanDiskCache.shared.luuTin(ds, cuocId: cuoc.id)
            await napNguoiLienQuan(kq.tin)
            taiTruocMediaTheoQuyDinh(kq.tin)
        } catch { loi = error.localizedDescription }
    }

    func danhDauDaDoc() {
        Task { try? await env.api.danhDauDaDoc(cuoc: cuoc.id) }
    }

    private func napNguoiLienQuan(_ ds: [Tin]) async {
        let uids = ds.flatMap { t -> [String] in
            var u = t.camXuc.map(\.uid)
            if !t.laToi, let x = t.uid { u.append(x) }
            return u
        }
        await env.napNguoi(uids)
    }

    private func taiTruocMediaTheoQuyDinh(_ ds: [Tin]) {
        let moc1Thang = Date().addingTimeInterval(-30 * 24 * 3600).timeIntervalSince1970 * 1000
        let moc1Tuan = Date().addingTimeInterval(-7 * 24 * 3600).timeIntervalSince1970 * 1000

        // Đảo ngược danh sách: ưu tiên tải trước các tin MỚI NHẤT TRƯỚC
        let tinMoi = ds.reversed()
        var urlsTai: [URL] = []
        for t in tinMoi {
            guard let f = t.file, let url = env.api.diaChiMedia(f) else { continue }
            let ts = t.ts

            // Ảnh/GIF/Sticker: tải trước nếu trong vòng 1 tháng
            if ["anh", "gif", "sticker"].contains(t.kieu) {
                if ts >= Int64(moc1Thang) {
                    urlsTai.append(url)
                }
            } else if t.kieu == "video" {
                // Video: tải trước nếu trong vòng 1 tháng
                if ts >= Int64(moc1Thang) && !MediaDiskCache.shared.daCo(cho: url) {
                    Task(priority: .background) {
                        _ = await MediaDiskCache.shared.taiVaLuuVideo(tu: url)
                    }
                }
            } else if t.kieu == "file" {
                // File: tải trước nếu trong vòng 1 tuần và kích thước <= 15MB
                if ts >= Int64(moc1Tuan) && !MediaDiskCache.shared.daCo(cho: url, tenFile: t.tenFile) {
                    let mb = Double(t.kichThuoc ?? 0) / (1024 * 1024)
                    if mb <= 15.0 {
                        Task(priority: .background) {
                            _ = await MediaDiskCache.shared.taiVaLuuFile(tu: url, tenFile: t.tenFile)
                        }
                    }
                }
            }
        }
        if !urlsTai.isEmpty {
            Task(priority: .background) {
                await MediaPrefetchQueue.shared.them(urls: urlsTai)
            }
        }
    }

    // ---------------------------------------------------------------- gửi
    func guiChu(_ chu: String, tag: [TagMark] = []) async {
        let noiDung = chu.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !noiDung.isEmpty else { return }
        let trich = traLoi?.msgId
        do {
            try await env.api.guiChu(cuoc: cuoc.id, chu: chu, tag: tag, trichMsgId: trich)
            traLoi = nil
            cuonToiMsgId = "__cuoi__"
        } catch { loi = "Không gửi được: " + error.localizedDescription }
    }

    func guiFile(duLieu: Data, tenFile: String) async {
        let trich = traLoi?.msgId
        do {
            try await env.api.guiFile(cuoc: cuoc.id, duLieu: duLieu, tenFile: tenFile, trichMsgId: trich)
            traLoi = nil
            cuonToiMsgId = "__cuoi__"
        } catch { loi = "Không gửi được \(tenFile): " + error.localizedDescription }
    }

    // ---------------------------------------------------------------- thao tác trên 1 tin
    func thaCamXuc(_ t: Tin, icon: String) async {
        guard t.duocThaCamXuc else { return }
        let daTha = t.camXucCuaToi(uidToi: env.uidToi).contains { $0.icon == icon }
        do { try await env.api.thaCamXuc(cuoc: cuoc.id, msg: t.msgId, icon: daTha ? "" : icon) }
        catch { loi = "Không thả được cảm xúc: " + error.localizedDescription }
    }

    func thuHoi(_ t: Tin) async {
        guard t.duocThuHoi else { return }
        do { try await env.api.thuHoiTin(cuoc: cuoc.id, msg: t.msgId) }
        catch { loi = "Không thu hồi được: " + error.localizedDescription }
    }

    func chonTraLoi(_ t: Tin) {
        traLoi = t
        cuonToiMsgId = "__cuoi__"
    }
    func boTraLoi() { traLoi = nil }

    // ---------------------------------------------------------------- realtime
    private func xuLySuKien(_ sk: SuKienZalo) {
        switch sk {
        case .tinMoi(let cuocId, let tin, let laTinMoi):
            guard cuocId == cuoc.id, !cheDoQuanh else { return }
            tinDangXem = PhanTrang.ganTin(tinDangXem, tin)
            TinNhanDiskCache.shared.capNhatTinMoi(tin: tin, cuocId: cuoc.id)
            Task { await napNguoiLienQuan([tin]) }
            taiTruocMediaTheoQuyDinh([tin])
            if laTinMoi { cuonToiMsgId = "__cuoi_neu_sat_day__" }
            if laTinMoi && !tin.laToi { danhDauDaDoc() }
        case .daDoc, .ghimDoiThayDoi:
            break
        case .ketNoiLai:
            Task { await taiBu() }
        }
    }

    /// Lấy 60 tin mới nhất, gộp vào (bắt được cả tin bị sửa/thu hồi trong lúc mất kết nối) - khớp taiBu() của web.
    private func taiBu() async {
        guard !cheDoQuanh else { return }
        do {
            let kq = try await env.api.dsTin(cuoc: cuoc.id)
            let cuoiCu = tinDangXem.last?.ts ?? 0
            let coMoi = kq.tin.contains { $0.ts > cuoiCu && !$0.laToi }
            if tinDangXem.isEmpty || (kq.tin.first.map { $0.ts > cuoiCu } ?? false) {
                tinDangXem = kq.tin
                heTin = kq.tin.count < 60
            } else {
                for t in kq.tin { tinDangXem = PhanTrang.ganTin(tinDangXem, t) }
            }
            TinNhanDiskCache.shared.luuTin(tinDangXem, cuocId: cuoc.id)
            await napNguoiLienQuan(kq.tin)
            taiTruocMediaTheoQuyDinh(kq.tin)
            if coMoi { cuonToiMsgId = "__cuoi_neu_sat_day__"; danhDauDaDoc() }
        } catch { /* mat mang tam thoi - bo qua, SSE se tu noi lai */ }
    }
}
