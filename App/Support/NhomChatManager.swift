// Quản lý các nhóm phân loại cuộc trò chuyện do người dùng tự tạo (ví dụ: Đặt hàng, Nhóm, Gia đình, ...).
// Tự động đồng bộ 2 chiều giữa thiết bị (UserDefaults) và máy chủ (/api/nhom-tuy-chon).

import Foundation
import Combine

@MainActor
final class NhomChatManager: ObservableObject {
    static let shared = NhomChatManager()

    private let KHOA_LUU_TRU = "nhom_chat_tuy_chon_v1"

    @Published var dsNhom: [NhomTuyChon] = []
    private weak var api: ZaloAPI?
    private var dangDongBo = false

    private init() {
        taiDanhSach()
    }

    func ganAPI(_ api: ZaloAPI) {
        self.api = api
    }

    func taiDanhSach() {
        guard let data = UserDefaults.standard.data(forKey: KHOA_LUU_TRU),
              let ds = try? JSONDecoder().decode([NhomTuyChon].self, from: data) else {
            // Mẫu ban đầu nếu chưa có nhóm nào: tạo sẵn nhóm "Đặt hàng" để người dùng dễ dùng ngay
            self.dsNhom = [
                NhomTuyChon(id: "dat-hang", ten: "Đặt hàng", dsCuocId: [])
            ]
            luuDanhSach()
            return
        }
        self.dsNhom = ds
    }

    func luuDanhSach() {
        if let data = try? JSONEncoder().encode(dsNhom) {
            UserDefaults.standard.set(data, forKey: KHOA_LUU_TRU)
        }
    }

    private func dayLenServer() {
        guard let api = self.api else { return }
        let ds = self.dsNhom
        Task {
            do {
                try await api.luuNhomTuyChon(ds)
                print("[NhomChatManager] Da day \(ds.count) nhom len server thanh cong")
            } catch {
                print("[NhomChatManager] Loi day nhom len server: \(error.localizedDescription)")
            }
        }
    }

    /// Đồng bộ 2 chiều với máy chủ: lấy từ server về, gộp an toàn với nhóm cục bộ (không làm mất nhóm nào),
    /// rồi cập nhật lại cả cục bộ lẫn máy chủ nếu có thay đổi.
    func dongBoVoiServer(api: ZaloAPI? = nil) async {
        if let api { self.api = api }
        guard let api = self.api, !dangDongBo else { return }
        dangDongBo = true
        defer { dangDongBo = false }

        do {
            let serverDs = try await api.layNhomTuyChon()
            let localDs = self.dsNhom

            // Logic gộp thông minh:
            // 1. Nếu server chỉ có 1 nhóm mặc định rỗng "dat-hang" mà local có nhóm thực tế -> ưu tiên đẩy local lên
            let serverLaMacDinh = serverDs.isEmpty || (serverDs.count == 1 && serverDs[0].id == "dat-hang" && serverDs[0].dsCuocId.isEmpty)
            let localCoDuLieu = localDs.contains { $0.id != "dat-hang" || !$0.dsCuocId.isEmpty }

            var ketQua = serverDs
            if serverLaMacDinh && localCoDuLieu {
                ketQua = localDs
            } else {
                // Gộp các nhóm ở local mà server chưa có
                for loc in localDs {
                    if let idx = ketQua.firstIndex(where: { $0.id == loc.id || $0.ten.caseInsensitiveCompare(loc.ten) == .orderedSame }) {
                        // Nhóm đã có cả 2 bên -> hợp nhất danh sách chat (union)
                        var cuocSet = Set(ketQua[idx].dsCuocId)
                        for c in loc.dsCuocId { cuocSet.insert(c) }
                        ketQua[idx].dsCuocId = Array(cuocSet)
                    } else {
                        // Nhóm chỉ có ở máy -> thêm vào danh sách kết quả
                        ketQua.append(loc)
                    }
                }
            }

            self.dsNhom = ketQua
            self.luuDanhSach()

            // Nếu danh sách gộp khác server (ví dụ có thêm nhóm từ máy) -> cập nhật ngược lên server
            if ketQua != serverDs {
                try await api.luuNhomTuyChon(ketQua)
                print("[NhomChatManager] Da dong bo va cap nhat \(ketQua.count) nhom len server")
            } else {
                print("[NhomChatManager] Dong bo nhom voi server hoan tat: \(ketQua.count) nhom")
            }
        } catch {
            print("[NhomChatManager] Khong the lay nhom tu server: \(error.localizedDescription)")
            // Khi không kết nối được server, vẫn giữ nguyên dữ liệu cục bộ
        }
    }

    /// Nhận danh sách cập nhật tức thời từ Server qua SSE (khi người dùng sửa trên web)
    func capNhatTuServer(_ ds: [NhomTuyChon]) {
        guard !ds.isEmpty else { return }
        self.dsNhom = ds
        luuDanhSach()
    }

    @discardableResult
    func taoNhom(ten: String) -> NhomTuyChon {
        let tenChuan = ten.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tenChuan.isEmpty else { return NhomTuyChon(ten: "Nhóm mới") }
        let moi = NhomTuyChon(ten: tenChuan)
        dsNhom.append(moi)
        luuDanhSach()
        dayLenServer()
        return moi
    }

    func doiTenNhom(id: String, tenMoi: String) {
        let tenChuan = tenMoi.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tenChuan.isEmpty, let idx = dsNhom.firstIndex(where: { $0.id == id }) else { return }
        dsNhom[idx].ten = tenChuan
        luuDanhSach()
        dayLenServer()
    }

    func xoaNhom(id: String) {
        dsNhom.removeAll(where: { $0.id == id })
        luuDanhSach()
        dayLenServer()
    }

    func themCuocVaoNhom(nhomId: String, cuocId: String) {
        guard !cuocId.isEmpty, let idx = dsNhom.firstIndex(where: { $0.id == nhomId }) else { return }
        if !dsNhom[idx].dsCuocId.contains(cuocId) {
            dsNhom[idx].dsCuocId.append(cuocId)
            luuDanhSach()
            dayLenServer()
        }
    }

    func xoaCuocKhoiNhom(nhomId: String, cuocId: String) {
        guard let idx = dsNhom.firstIndex(where: { $0.id == nhomId }) else { return }
        dsNhom[idx].dsCuocId.removeAll(where: { $0 == cuocId })
        luuDanhSach()
        dayLenServer()
    }

    /// Cập nhật toàn bộ các nhóm mà cuộc trò chuyện này thuộc về
    func datNhomChoCuoc(cuocId: String, cacNhomId: Set<String>) {
        guard !cuocId.isEmpty else { return }
        for i in 0..<dsNhom.count {
            let nhomId = dsNhom[i].id
            let coTrongNhom = dsNhom[i].dsCuocId.contains(cuocId)
            let muonCo = cacNhomId.contains(nhomId)

            if muonCo && !coTrongNhom {
                dsNhom[i].dsCuocId.append(cuocId)
            } else if !muonCo && coTrongNhom {
                dsNhom[i].dsCuocId.removeAll(where: { $0 == cuocId })
            }
        }
        luuDanhSach()
        dayLenServer()
    }

    /// Lấy danh sách ID các nhóm mà cuocId đang thuộc về
    func dsNhomIdCuaCuoc(cuocId: String) -> Set<String> {
        guard !cuocId.isEmpty else { return [] }
        let ketQua = dsNhom.filter { $0.dsCuocId.contains(cuocId) }.map { $0.id }
        return Set(ketQua)
    }

    /// Lấy danh sách đối tượng nhóm mà cuocId đang thuộc về
    func cacNhomCuaCuoc(cuocId: String) -> [NhomTuyChon] {
        guard !cuocId.isEmpty else { return [] }
        return dsNhom.filter { $0.dsCuocId.contains(cuocId) }
    }
}
