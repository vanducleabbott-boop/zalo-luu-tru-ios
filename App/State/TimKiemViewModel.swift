// v5.7: tìm kiếm chung cho tab "Tin nhắn" và tab "Nhóm": người & nhóm, tin nhắn, file - đều KHÔNG DẤU.
// Gộp 3 nguồn: dữ liệu trên máy (tức thì) + /api/cuoc?tim + /api/tim, và danh sách file (/api/kho loai=file)
// của các cuộc gần đây (tải 1 lần, giữ 5 phút) để tìm theo tên file.

import Foundation
import Combine

@MainActor
final class TimKiemViewModel: ObservableObject {
    @Published var tuKhoa = "" { didSet { if tuKhoa != oldValue { henTim() } } }
    @Published private(set) var ketQuaNhom: [NhomTuyChon] = []
    @Published private(set) var ketQuaCuoc: [Cuoc] = []
    @Published private(set) var ketQuaTin: [Tin] = []
    @Published private(set) var ketQuaFile: [Tin] = []
    @Published private(set) var dangTim = false

    private let env: AppEnvironment
    /// true = tab Nhóm: chỉ tìm trong các cuộc đã xếp vào nhóm tuỳ chọn (+ tên nhóm).
    private let chiTrongNhom: Bool
    private var viecTim: Task<Void, Never>?

    private static var khoFile: [String: [Tin]] = [:]
    private static var khoFileLuc = Date.distantPast
    private static var dangNapKhoFile: Task<Void, Never>?

    init(env: AppEnvironment, chiTrongNhom: Bool = false) {
        self.env = env
        self.chiTrongNhom = chiTrongNhom
    }

    var dangTimKiem: Bool { !tuKhoa.trimmingCharacters(in: .whitespaces).isEmpty }
    var khongCoKetQua: Bool { ketQuaNhom.isEmpty && ketQuaCuoc.isEmpty && ketQuaTin.isEmpty && ketQuaFile.isEmpty }

    /// Mã các cuộc được phép xuất hiện (nil = mọi cuộc).
    private var phamVi: Set<String>? {
        chiTrongNhom ? Set(NhomChatManager.shared.dsNhom.flatMap(\.dsCuocId)) : nil
    }

    private func trongPhamVi(_ cuocId: String?) -> Bool {
        guard let pv = phamVi else { return true }
        return cuocId.map { pv.contains($0) } ?? false
    }

    static func laFile(_ t: Tin) -> Bool { t.kieu == "file" }

    private func henTim() {
        viecTim?.cancel()
        let tu = tuKhoa
        guard dangTimKiem else {
            ketQuaNhom = []; ketQuaCuoc = []; ketQuaTin = []; ketQuaFile = []; dangTim = false
            return
        }
        viecTim = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await self?.timNgay(tu)
        }
    }

    private func timNgay(_ tu: String) async {
        dangTim = true
        defer { if tu == tuKhoa { dangTim = false } }
        let cache = env.dsCuocCache

        // 1. Trên máy: hiện ngay
        if chiTrongNhom { ketQuaNhom = NhomChatManager.shared.dsNhom.filter { $0.ten.khopKhongDau(tu) } }
        ketQuaCuoc = timCuocTrenMay(tu)
        let tinMay = await Task.detached(priority: .userInitiated) {
            TinNhanDiskCache.shared.timTin(tu, toiDa: 300).map { $0.tin.ganCuoc(cache[$0.cuocId], cuocId: $0.cuocId) }
        }.value.filter { trongPhamVi($0.cuocId) }
        guard tu == tuKhoa else { return }
        ganTin(tinMay)
        ganFile(timTrongKhoFile(tu))

        // 2. Máy chủ (tìm đúng dấu) + danh sách file các cuộc gần đây
        async let cuoc = try? env.api.dsCuoc(tim: tu)
        async let tin = try? env.api.timKiemChung(q: tu)
        let (c, t) = await (cuoc, tin)
        guard tu == tuKhoa, !Task.isCancelled else { return }
        let daCo = Set(ketQuaCuoc.map(\.id))
        ketQuaCuoc += (c ?? []).filter { !daCo.contains($0.id) && trongPhamVi($0.id) }
        ganTin((t ?? []).filter { trongPhamVi($0.cuocId) })

        await napKhoFile()
        guard tu == tuKhoa else { return }
        ganFile(timTrongKhoFile(tu))
    }

    /// Gộp thêm tin vào kết quả: tin có file -> mục File, còn lại -> Tin nhắn. Bỏ trùng, mới nhất trước.
    private func ganTin(_ ds: [Tin]) {
        ganFile(ds.filter(Self.laFile))
        var gap = Set(ketQuaTin.map(\.msgId))
        ketQuaTin = (ketQuaTin + ds.filter { !Self.laFile($0) && gap.insert($0.msgId).inserted })
            .sorted { $0.ts > $1.ts }
    }

    private func ganFile(_ ds: [Tin]) {
        var gap = Set(ketQuaFile.map(\.msgId))
        ketQuaFile = (ketQuaFile + ds.filter { gap.insert($0.msgId).inserted }).sorted { $0.ts > $1.ts }
    }

    private func timTrongKhoFile(_ tu: String) -> [Tin] {
        let cache = env.dsCuocCache
        return Self.khoFile.flatMap { cuocId, ds in
            trongPhamVi(cuocId) ? ds.filter { ($0.tenFile ?? "").khopKhongDau(tu) }.map { $0.ganCuoc(cache[cuocId], cuocId: cuocId) } : []
        }
    }

    /// Tải trang file mới nhất của các cuộc trong phạm vi (tab Nhóm) hoặc 40 cuộc gần nhất (tab Tin nhắn).
    private func napKhoFile() async {
        if let dang = Self.dangNapKhoFile { await dang.value; return }
        let dsCuoc: [String]
        if let pv = phamVi { dsCuoc = Array(pv) }
        else {
            dsCuoc = env.dsCuocCache.values.sorted { ($0.tinCuoiTs ?? 0) > ($1.tinCuoiTs ?? 0) }.prefix(40).map(\.id)
        }
        let conThieu = Date().timeIntervalSince(Self.khoFileLuc) > 300 ? dsCuoc : dsCuoc.filter { Self.khoFile[$0] == nil }
        guard !conThieu.isEmpty else { return }
        let api = env.api
        let viec = Task {
            await withTaskGroup(of: (String, [Tin]?).self) { nhom in
                for id in conThieu {
                    nhom.addTask { (id, try? await api.layKho(cuoc: id, loai: "file").ds) }
                }
                for await (id, ds) in nhom { if let ds { Self.khoFile[id] = ds } }
            }
            Self.khoFileLuc = Date()
        }
        Self.dangNapKhoFile = viec
        await viec.value
        Self.dangNapKhoFile = nil
    }

    /// Người & nhóm khớp không dấu: tên bắt đầu bằng từ khoá (hoặc 1 từ trong tên bắt đầu bằng nó) lên trước.
    private func timCuocTrenMay(_ tu: String) -> [Cuoc] {
        let q = tu.trimmingCharacters(in: .whitespaces).boDau
        func hang(_ c: Cuoc) -> Int {
            let ten = (c.ten ?? c.id).boDau
            if ten.hasPrefix(q) { return 0 }
            return ten.split(separator: " ").contains { $0.hasPrefix(q) } ? 1 : 2
        }
        return env.dsCuocCache.values
            .filter { trongPhamVi($0.id) && ($0.ten ?? $0.id).khopKhongDau(q) }
            .sorted { (hang($0), -($0.tinCuoiTs ?? 0)) < (hang($1), -($1.tinCuoiTs ?? 0)) }
    }
}
