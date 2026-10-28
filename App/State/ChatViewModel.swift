// 1 cuộc trò chuyện đang mở: tải tin, cuộn lên tải tin cũ, gửi/thu hồi/thả cảm xúc, cập nhật realtime.
// Khớp moCuoc()/taiTinCu()/taiBu()/guiChu()/thaCamXuc() trong web/index.html.

import Foundation
import Combine
import UIKit

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
    /// v5.4: khoá mục (MucHienThi.khoa) cần giữ nguyên trên màn hình sau khi nạp thêm tin cũ.
    @Published var giuViTriKhoa: String?
    @Published private(set) var thanhVienNhom: [ThanhVien] = []
    @Published private(set) var dangTaiThanhVien = false
    @Published var dsGhim: [TinGhim] = []
    @Published var tinDuocNhayToi: String? = nil

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

    /// v5.6: mục kèm khoá CHẮC CHẮN duy nhất cho List (khoá trùng làm List crash) - trùng thì thêm "#n".
    var mucCoKhoa: [(khoa: String, muc: GomNhom.MucHienThi)] {
        var dem: [String: Int] = [:]
        return danhSachHienThi.map { m in
            let k = m.khoa
            let n = dem[k, default: 0]
            dem[k] = n + 1
            return (n == 0 ? k : "\(k)#\(n)", m)
        }
    }

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
            if let g = kq.dsGhim { dsGhim = g }
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
            if cuoc.laNhomBool {
                Task { await taiThanhVienNhom() }
            }
        } catch {
            if tinDangXem.isEmpty { loi = error.localizedDescription }
        }
    }

    func taiThanhVienNhom() async {
        guard cuoc.laNhomBool, !dangTaiThanhVien else { return }
        dangTaiThanhVien = true
        defer { dangTaiThanhVien = false }
        do {
            let ds = try await env.api.layThanhVien(cuoc: cuoc.id)
            thanhVienNhom = ds
            let uids = ds.map(\.uid)
            await env.napNguoi(uids)
        } catch {
            print("[ChatViewModel] Khong lay duoc thanh vien nhom \(cuoc.id): \(error.localizedDescription)")
        }
    }

    func taiTinCu() async {
        guard daCuonXuongCuoiLanDau, !heTin, !dangTaiTinCu, let dauTien = tinDangXem.first else { return }
        dangTaiTinCu = true
        defer { dangTaiTinCu = false }
        do {
            let kq = try await env.api.dsTin(cuoc: cuoc.id, truoc: dauTien.ts)
            let (ds, het) = PhanTrang.noiTrangCu(hienTai: tinDangXem, trangCu: kq.tin)
            let neo = danhSachHienThi.first(where: { if case .ngay = $0 { return false } else { return true } })?.khoa
            tinDangXem = ds
            if !kq.tin.isEmpty { giuViTriKhoa = neo }
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
    @discardableResult
    func guiChu(_ chu: String, tag: [TagMark] = []) async -> Bool {
        let noiDung = chu.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !noiDung.isEmpty else { return false }
        let trich = traLoi?.msgId
        do {
            try await env.api.guiChu(cuoc: cuoc.id, chu: chu, tag: tag, trichMsgId: trich)
            ChiaSeChung.baoDaNhan(cuoc.nguoiNhanChiaSe)
            traLoi = nil
            cuonToiMsgId = "__cuoi__"
            return true
        } catch { loi = "Không gửi được: " + error.localizedDescription; return false }
    }

    func guiFile(duLieu: Data, tenFile: String) async {
        let trich = traLoi?.msgId
        traLoi = nil

        // 1. Phân loại kiểu tin (ảnh / video / file)
        let ext = (tenFile as NSString).pathExtension.lowercased()
        let kieu: String
        if ["jpg", "jpeg", "png", "webp", "gif"].contains(ext) {
            kieu = "anh"
        } else if ["mp4", "mov"].contains(ext) {
            kieu = "video"
        } else {
            kieu = "file"
        }

        // 2. Lưu đĩa cục bộ tức thì để hiển thị ngay 0ms không cần chờ server tải về
        let localURL = MediaDiskCache.shared.luuMediaCucBo(data: duLieu, tenFile: tenFile)

        // Nếu là ảnh, cache sẵn trong RAM để hiển thị tức thì không khựng
        if kieu == "anh", let img = UIImage(data: duLieu) {
            let khoa = MediaDiskCache.shared.khoaCache(tu: localURL)
            ImageCacheManager.shared.luuAnh(img, khoa: khoa, dungLuong: duLieu.count)
        }

        // 3. Tạo tin nhắn tạm (optimistic preview) chèn ngay vào danh sách chat
        let tempId = "temp_\(UUID().uuidString)"
        let trichDan = trich.flatMap { msgId in
            tinDangXem.first(where: { $0.msgId == msgId }).map {
                TrichDan(ten: $0.tenNguoi, chu: $0.chu ?? $0.tenFile, msgId: $0.msgId)
            }
        }
        let tinTam = Tin(
            msgId: tempId,
            cliMsgId: tempId,
            cuocId: cuoc.id,
            uid: env.uidToi,
            tenNguoi: "Tôi",
            laToi: true,
            ts: Int64(Date().timeIntervalSince1970 * 1000),
            loai: "gui",
            kieu: kieu,
            chu: nil,
            url: nil,
            file: localURL.absoluteString,
            tenFile: tenFile,
            kichThuoc: Int64(duLieu.count),
            quote: trichDan,
            thuHoi: false,
            phu: nil,
            camXuc: [],
            tenCuoc: nil,
            laNhomCuoc: nil
        )

        tinDangXem = PhanTrang.ganTin(tinDangXem, tinTam)
        cuonToiMsgId = "__cuoi__"

        // 4. Gửi file lên server ngầm
        do {
            try await env.api.guiFile(cuoc: cuoc.id, duLieu: duLieu, tenFile: tenFile, trichMsgId: trich)
            ChiaSeChung.baoDaNhan(cuoc.nguoiNhanChiaSe)
        } catch {
            loi = "Không gửi được \(tenFile): " + error.localizedDescription
            tinDangXem.removeAll(where: { $0.msgId == tempId })
        }
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

    /// Gửi nhiều ảnh/video 1 lần thành ALBUM (như Zalo gốc). 1 tệp thì gửi thường.
    func guiAlbum(_ tep: [(duLieu: Data, tenFile: String)]) async {
        guard !tep.isEmpty else { return }
        if tep.count == 1 { await guiFile(duLieu: tep[0].duLieu, tenFile: tep[0].tenFile); return }
        traLoi = nil   // Zalo không trích dẫn kèm album
        do {
            var ma: [String] = []
            for t in tep { ma.append(try await env.api.taiLenTam(duLieu: t.duLieu, tenFile: t.tenFile)) }
            try await env.api.guiAlbum(cuoc: cuoc.id, ma: ma)
            cuonToiMsgId = "__cuoi__"
        } catch { loi = "Không gửi được album: " + error.localizedDescription }
    }

    /// Gửi sticker từ bảng chọn. Zalo không cho trích dẫn kèm sticker -> đang trả lời thì sticker gửi thành tin thường.
    func guiSticker(_ s: StickerTrongKho) async {
        do {
            try await env.api.guiSticker(cuoc: cuoc.id, id: s.id)
            traLoi = nil
            cuonToiMsgId = "__cuoi__"
        } catch { loi = "Không gửi được sticker: " + error.localizedDescription }
    }

    // ---------------------------------------------------------------- lịch hẹn (nhắc hẹn)
    func taoLichHen(tieuDe: String, batDau: Date, lap: Int, emoji: String, chiaSe: Bool) async throws {
        let batDauMs = Int64(batDau.timeIntervalSince1970 * 1000)
        _ = try await env.api.taoLichHen(cuoc: cuoc.id, tieuDe: tieuDe, batDau: batDauMs, lap: lap, emoji: emoji, chiaSe: chiaSe)
        cuonToiMsgId = "__cuoi__"
    }

    func xoaLichHen(id: String, cuocId: String? = nil) async {
        do {
            try await env.api.xoaLichHen(cuoc: cuocId ?? cuoc.id, id: id)
        } catch {
            loi = "Không thể xoá lịch hẹn: " + error.localizedDescription
        }
    }

    // ---------------------------------------------------------------- tin nhắn đã ghim
    func laTinGhim(_ msgId: String) -> Bool {
        dsGhim.contains { $0.msgId == msgId }
    }

    func chuyenTrangThaiGhim(_ t: Tin) async {
        let daGhim = laTinGhim(t.msgId)
        let tieuDe = (t.chu?.isEmpty == false ? t.chu : (t.tenFile ?? t.kieu)) ?? ""
        await chuyenTrangThaiGhim(msgId: t.msgId, ghim: !daGhim, tieuDe: String(tieuDe.prefix(100)))
    }

    func chuyenTrangThaiGhim(msgId: String, ghim: Bool, tieuDe: String = "") async {
        do {
            let moi = try await env.api.datTinGhim(cuoc: cuoc.id, msgId: msgId, ghim: ghim, tieuDe: tieuDe)
            dsGhim = moi
        } catch {
            loi = "Lỗi đổi ghim tin: " + error.localizedDescription
        }
    }

    // ---------------------------------------------------------------- realtime
    private func xuLySuKien(_ sk: SuKienZalo) {
        switch sk {
        case .tinGhimThayDoi(let cId, let ghimMoi):
            if cId == cuoc.id {
                dsGhim = ghimMoi
            }
        case .tinMoi(let cuocId, let tin, let laTinMoi):
            guard cuocId == cuoc.id, !cheDoQuanh else { return }

            // Nếu là tin tôi vừa gửi, chuyển bộ đệm từ tin tạm sang URL chính thức của server
            if tin.laToi {
                if let idx = tinDangXem.firstIndex(where: { $0.msgId.hasPrefix("temp_") && ($0.tenFile == tin.tenFile || $0.kieu == tin.kieu) }) {
                    let tinTam = tinDangXem[idx]
                    if let tempPath = tinTam.file, let tempURL = URL(string: tempPath),
                       let serverURL = tin.file.flatMap({ env.api.diaChiMedia($0) }) {
                        if let data = try? Data(contentsOf: tempURL) {
                            MediaDiskCache.shared.luuDuLieu(data, cho: serverURL)
                            if tin.kieu == "anh", let img = UIImage(data: data) {
                                let khoa = MediaDiskCache.shared.khoaCache(tu: serverURL)
                                ImageCacheManager.shared.luuAnh(img, khoa: khoa, dungLuong: data.count)
                            }
                        }
                    }
                    tinDangXem.remove(at: idx)
                }
            }

            tinDangXem = PhanTrang.ganTin(tinDangXem, tin)
            TinNhanDiskCache.shared.capNhatTinMoi(tin: tin, cuocId: cuoc.id)
            Task { await napNguoiLienQuan([tin]) }
            taiTruocMediaTheoQuyDinh([tin])
            if laTinMoi { cuonToiMsgId = "__cuoi_neu_sat_day__" }
            if laTinMoi && !tin.laToi { danhDauDaDoc() }
        case .daDoc, .ghimDoiThayDoi:
            break
        case .binhChonThayDoi(let cId, let pollId):
            if cId == cuoc.id {
                Task { await capNhatBinhChonRealtime(pollId: pollId) }
            }
        case .ketNoiLai:
            Task { await taiBu() }
        default:
            break
        }
    }

    // ---------------------------------------------------------------- bình chọn nhóm (poll)
    func boPhieu(pollId: String, optionIds: [Int]) async throws -> BinhChonInfo {
        let kq = try await env.api.boPhieuBinhChon(pollId: pollId, cuocId: cuoc.id, optionIds: optionIds)
        capNhatBinhChonTrongDanhSach(kq)
        return kq
    }

    func capNhatBinhChonRealtime(pollId: String) async {
        guard !pollId.isEmpty else {
            await taiBu()
            return
        }
        do {
            let moi = try await env.api.layChiTietBinhChon(pollId: pollId)
            capNhatBinhChonTrongDanhSach(moi)
        } catch {
            await taiBu()
        }
    }

    /// Thay bình chọn trong các tin đang xem: gán mảng 1 lần (1 lần vẽ lại) và ghi bộ đệm đĩa 1 lần.
    private func capNhatBinhChonTrongDanhSach(_ bc: BinhChonInfo) {
        var ds = tinDangXem
        var coDoi = false
        for i in ds.indices where ds[i].phu?.binhChon?.pollId == bc.pollId && ds[i].phu?.binhChon != bc {
            let p = ds[i].phu ?? Phu()
            ds[i] = ds[i].voiPhu(Phu(khung: p.khung, ms: p.ms, lich: p.lich, tag: p.tag, cuocNguon: p.cuocNguon,
                                     album: p.album, danhThiep: p.danhThiep, chuyenKhoan: p.chuyenKhoan, binhChon: bc))
            coDoi = true
        }
        guard coDoi else { return }
        tinDangXem = ds
        if !cheDoQuanh { TinNhanDiskCache.shared.luuTin(ds, cuocId: cuoc.id) }
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
