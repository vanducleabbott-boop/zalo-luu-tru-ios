// Danh sách hội thoại bên trái (tab "Tin nhắn"): tải, tìm kiếm, ghim/tắt thông báo, cập nhật realtime.
// Khớp taiDanhSach()/veDanhSach()/dongMuc() trong web/index.html.

import Foundation
import Combine

@MainActor
final class ConversationListViewModel: ObservableObject {
    @Published var dsCuoc: [Cuoc] = []
    @Published var ketQuaTimCuoc: [Cuoc] = []
    @Published var ketQuaTimTin: [Tin] = []
    @Published var dangTim = false
    @Published var loi: String?
    @Published var dangTai = false

    private let env: AppEnvironment
    private var huyTheoDoi = Set<AnyCancellable>()
    private var henTaiLai: Task<Void, Never>?

    @Published var tuKhoaTim: String = "" {
        didSet { timKiemSau() }
    }

    init(env: AppEnvironment) {
        self.env = env
        env.sse.suKien
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sk in self?.xuLySuKien(sk) }
            .store(in: &huyTheoDoi)
    }

    func tai() async {
        dangTai = true
        defer { dangTai = false }
        do {
            dsCuoc = try await env.api.dsCuoc()
            for c in dsCuoc { env.dsCuocCache[c.id] = c }
            await napTenNguoiChuaCo()
            taiTruocTinNhanVaMedia()
        } catch { loi = error.localizedDescription }
    }

    private func taiTruocTinNhanVaMedia() {
        Task(priority: .background) { [weak self] in
            guard let self = self else { return }
            // Tải trước tin nhắn (text nhẹ) và media theo quy định:
            // - Tin nhắn: tải sẵn vào đĩa để mở tức thì 0ms
            // - File tài liệu: tải trước và lưu trong 1 tuần (7 ngày, tệp <= 15MB)
            // - Ảnh & Video: tải trước và lưu trong 1 tháng (30 ngày)
            // - Cũ hơn mốc này: không tải trước, người dùng bấm vào mới tải
            let danhSachCuoc = Array(self.dsCuoc.prefix(30))
            let moc1Thang = Date().addingTimeInterval(-30 * 24 * 3600).timeIntervalSince1970 * 1000
            let moc1Tuan = Date().addingTimeInterval(-7 * 24 * 3600).timeIntervalSince1970 * 1000

            for c in danhSachCuoc {
                do {
                    let ph = try await self.env.api.dsTin(cuoc: c.id)
                    // 1. Lưu tin nhắn vào cache đĩa
                    TinNhanDiskCache.shared.luuTin(ph.tin, cuocId: c.id)

                    // 2. Nạp trước thông tin người gửi
                    let uids = ph.tin.compactMap { $0.uid }.filter { !$0.isEmpty }
                    if !uids.isEmpty {
                        await self.env.napNguoi(uids)
                    }

                    // 3. Tải trước media
                    var urlsAnh: [URL] = []
                    for t in ph.tin.reversed() {
                        guard let f = t.file, let u = self.env.api.diaChiMedia(f) else { continue }
                        let ts = t.ts

                        // Ảnh/GIF/Sticker trong 1 tháng
                        if ["anh", "gif", "sticker"].contains(t.kieu) {
                            if ts >= Int64(moc1Thang) {
                                urlsAnh.append(u)
                            }
                        } else if t.kieu == "video" {
                            // Video trong 1 tháng
                            if ts >= Int64(moc1Thang) && !MediaDiskCache.shared.daCo(cho: u) {
                                _ = await MediaDiskCache.shared.taiVaLuuVideo(tu: u)
                            }
                        } else if t.kieu == "file" {
                            // File tài liệu trong 1 tuần (kích thước <= 15MB)
                            if ts >= Int64(moc1Tuan) && !MediaDiskCache.shared.daCo(cho: u, tenFile: t.tenFile) {
                                let mb = Double(t.kichThuoc ?? 0) / (1024 * 1024)
                                if mb <= 15.0 {
                                    _ = await MediaDiskCache.shared.taiVaLuuFile(tu: u, tenFile: t.tenFile)
                                }
                            }
                        }
                    }

                    if !urlsAnh.isEmpty {
                        await MediaPrefetchQueue.shared.them(urls: urlsAnh)
                    }

                    // Nghỉ 50ms giữa các cuộc để không làm nghẽn mạng
                    try? await Task.sleep(nanoseconds: 50_000_000)
                } catch {}
            }
        }
    }

    private func napTenNguoiChuaCo() async {
        // "Bạn: ..." hay ten nguoi gui cuoi trong nhom lay tu tinCuoi.ten (server da ghi san), khong can goi /api/nguoi o day.
    }

    private func timKiemSau() {
        henTaiLai?.cancel()
        let tu = tuKhoaTim
        guard !tu.trimmingCharacters(in: .whitespaces).isEmpty else { ketQuaTimCuoc = []; ketQuaTimTin = []; dangTim = false; return }
        henTaiLai = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.timNgay(tu)
        }
    }

    private func timNgay(_ tu: String) async {
        dangTim = true
        defer { dangTim = false }
        do {
            async let cuoc = env.api.dsCuoc(tim: tu)
            async let tin = env.api.timKiemChung(q: tu)
            let (c, t) = try await (cuoc, tin)
            guard tu == tuKhoaTim else { return }   // da go tiep, bo ket qua cu
            ketQuaTimCuoc = c
            ketQuaTimTin = t
        } catch { loi = error.localizedDescription }
    }

    func datGhim(_ c: Cuoc, bat: Bool) async {
        do { _ = try await env.api.datGhim(cuoc: c.id, bat: bat); await tai() } catch { loi = error.localizedDescription }
    }

    func datTatThongBao(_ c: Cuoc, tat: Bool) async {
        do { try await env.api.datTatThongBao(cuoc: c.id, tat: tat); await tai() } catch { loi = error.localizedDescription }
    }

    func lamMoiDanhBa() async -> Int? {
        try? await env.api.lamMoiDanhBa().so
    }

    /// Tổng số chưa đọc (trừ cuộc đang mở) - dùng cho badge icon tab, giống capNhatTieuDe() của web.
    func tongChuaDoc(cuocDangMo: String?) -> Int {
        dsCuoc.reduce(0) { $0 + (($1.id == cuocDangMo) ? 0 : $1.chuaDoc) }
    }

    private func xuLySuKien(_ sk: SuKienZalo) {
        switch sk {
        case .tinMoi(let cuocId, let tin, _):
            TinNhanDiskCache.shared.capNhatTinMoi(tin: tin, cuocId: cuocId)
            henTaiLaiDanhSach()
        case .daDoc, .ghimDoiThayDoi, .ketNoiLai:
            henTaiLaiDanhSach()
        }
    }

    private var henTai: Task<Void, Never>?
    private func henTaiLaiDanhSach() {
        henTai?.cancel()
        henTai = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.tai()
        }
    }
}
