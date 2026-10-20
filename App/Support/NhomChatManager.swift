// Quản lý các nhóm phân loại cuộc trò chuyện do người dùng tự tạo (ví dụ: Đặt hàng, Nhóm, Gia đình, ...).
// Lưu trữ cục bộ trên thiết bị qua UserDefaults.

import Foundation
import Combine

@MainActor
final class NhomChatManager: ObservableObject {
    static let shared = NhomChatManager()

    private let KHOA_LUU_TRU = "nhom_chat_tuy_chon_v1"

    @Published var dsNhom: [NhomTuyChon] = []

    private init() {
        taiDanhSach()
    }

    func taiDanhSach() {
        guard let data = UserDefaults.standard.data(forKey: KHOA_LUU_TRU),
              let ds = try? JSONDecoder().decode([NhomTuyChon].self, from: data) else {
            // Mẫu ban đầu nếu chưa có nhóm nào: tạo sẵn nhóm "Đặt hàng" để người dùng dễ dùng ngay
            self.dsNhom = [
                NhomTuyChon(ten: "Đặt hàng", dsCuocId: [])
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

    @discardableResult
    func taoNhom(ten: String) -> NhomTuyChon {
        let tenChuan = ten.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tenChuan.isEmpty else { return NhomTuyChon(ten: "Nhóm mới") }
        let moi = NhomTuyChon(ten: tenChuan)
        dsNhom.append(moi)
        luuDanhSach()
        return moi
    }

    func doiTenNhom(id: String, tenMoi: String) {
        let tenChuan = tenMoi.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tenChuan.isEmpty, let idx = dsNhom.firstIndex(where: { $0.id == id }) else { return }
        dsNhom[idx].ten = tenChuan
        luuDanhSach()
    }

    func xoaNhom(id: String) {
        dsNhom.removeAll(where: { $0.id == id })
        luuDanhSach()
    }

    func themCuocVaoNhom(nhomId: String, cuocId: String) {
        guard !cuocId.isEmpty, let idx = dsNhom.firstIndex(where: { $0.id == nhomId }) else { return }
        if !dsNhom[idx].dsCuocId.contains(cuocId) {
            dsNhom[idx].dsCuocId.append(cuocId)
            luuDanhSach()
        }
    }

    func xoaCuocKhoiNhom(nhomId: String, cuocId: String) {
        guard let idx = dsNhom.firstIndex(where: { $0.id == nhomId }) else { return }
        dsNhom[idx].dsCuocId.removeAll(where: { $0 == cuocId })
        luuDanhSach()
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
