// Đối tượng trung tâm: địa chỉ máy chủ, phiên đăng nhập, cache tên/ảnh người dùng, kết nối thời gian thực.
// Tiêm vào toàn bộ View qua @EnvironmentObject.

import Foundation
import Combine
import UIKit

@MainActor
final class AppEnvironment: ObservableObject {
    @Published private(set) var settings: AppSettings
    @Published private(set) var api: ZaloAPI
    @Published var daDangNhap = false
    @Published var dangKiemTraPhien = true
    @Published var uidToi: String = ""
    @Published private(set) var nguoiCache: [String: Nguoi] = [:]
    /// Tên/ảnh/trạng thái tắt-thông-báo của hội thoại - ConversationListViewModel cập nhật mỗi lần tải danh sách.
    /// Dùng để ghi đúng tiêu đề + tôn trọng "đã tắt thông báo nhóm" khi báo tin cục bộ lúc app ở nền.
    @Published var dsCuocCache: [String: Cuoc] = [:]
    let sse = SSEManager()
    private var huyTheoDoiThongBao: AnyCancellable?

    init() {
        let s = AppSettings()
        settings = s
        api = ZaloAPI(baseURL: s.baseURL)
        NotificationManager.shared.xinQuyen()
        BackgroundAudioManager.shared.batDauChayNen()
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            BackgroundAudioManager.shared.batDauChayNen()
        }
        huyTheoDoiThongBao = sse.suKien.receive(on: DispatchQueue.main).sink { [weak self] sk in self?.xuLyThongBaoNen(sk) }
    }

    private func xuLyThongBaoNen(_ sk: SuKienZalo) {
        guard case .tinMoi(let cuocId, let tin, let laTinMoi) = sk, laTinMoi else { return }
        let c = dsCuocCache[cuocId]
        let ten = c?.ten ?? tin.tenNguoi ?? tin.tenCuoc ?? (cuocId == "so_tay" ? "Cloud của tôi" : "Tin nhắn Zalo")
        NotificationManager.shared.baoTinMoiNeuCan(cuocId: cuocId, tin: tin, tenCuoc: ten,
                                                    laNhom: c?.laNhomBool ?? false, daTatThongBaoNhom: c?.daTatThongBao ?? false)
    }

    func doiMayChu(_ diaChi: String) {
        guard diaChi != settings.diaChiMayChu else { return }
        dangXuat()
        settings.diaChiMayChu = diaChi
        api = ZaloAPI(baseURL: settings.baseURL)
        nguoiCache = [:]
    }

    func kiemTraPhienDaCo() {
        daDangNhap = api.daCoCookiePhien()
        dangKiemTraPhien = false
        if daDangNhap { sse.batDau(api: api) }
    }

    func dangNhap(matKhau: String) async throws -> Bool {
        let ok = try await api.dangNhap(matKhau: matKhau)
        if ok {
            daDangNhap = true
            BackgroundAudioManager.shared.batDauChayNen()
            sse.batDau(api: api)
        }
        return ok
    }

    func dangXuat() {
        api.dangXuat()
        sse.dungHan()
        BackgroundAudioManager.shared.dungChayNen()
        daDangNhap = false
    }

    /// Nạp tên/ảnh của các uid chưa có trong cache (giống `napNguoi()` trong web).
    func napNguoi(_ uids: [String]) async {
        let can = Array(Set(uids.filter { !$0.isEmpty && nguoiCache[$0] == nil }))
        guard !can.isEmpty else { return }
        if let kq = try? await api.layNguoi(uids: can) {
            for (k, v) in kq { if let v { nguoiCache[k] = v } }
        }
    }

    func tenNguoi(uid: String?, macDinh: String?) -> String {
        guard let uid, let n = nguoiCache[uid]?.ten, !n.isEmpty else { return macDinh ?? uid ?? "" }
        return n
    }

    func anhNguoi(uid: String?) -> String? { uid.flatMap { nguoiCache[$0]?.anh } }
}
