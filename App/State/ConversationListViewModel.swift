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
            taiTruocMediaCacCuocDau()
        } catch { loi = error.localizedDescription }
    }

    private func taiTruocMediaCacCuocDau() {
        Task(priority: .background) { [weak self] in
            guard let self = self else { return }
            // Tải trước ngầm ảnh/tệp của 4 cuộc trò chuyện hoạt động gần đây nhất
            let topCuoc = Array(self.dsCuoc.prefix(4))
            for c in topCuoc {
                do {
                    let ph = try await self.env.api.dsTin(cuoc: c.id)
                    let moc1Thang = Date().addingTimeInterval(-30 * 24 * 3600).timeIntervalSince1970 * 1000
                    let tinGanDay = ph.tin.suffix(15).filter { $0.ts >= Int64(moc1Thang) }.reversed()
                    var urls: [URL] = []
                    for t in tinGanDay {
                        guard let f = t.file, let u = self.env.api.diaChiMedia(f) else { continue }
                        if ["anh", "gif", "sticker"].contains(t.kieu) {
                            urls.append(u)
                        }
                    }
                    if !urls.isEmpty {
                        await MediaPrefetchQueue.shared.them(urls: urls)
                    }
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
        case .tinMoi, .daDoc, .ghimDoiThayDoi, .ketNoiLai:
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
