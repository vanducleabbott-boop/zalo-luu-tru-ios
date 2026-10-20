// Đối tượng trung tâm: địa chỉ máy chủ, phiên đăng nhập, cache tên/ảnh người dùng, kết nối thời gian thực.
// Tiêm vào toàn bộ View qua @EnvironmentObject.

import Foundation
import Combine
import UIKit
import SwiftUI

struct YeuCauMoCuoc: Hashable, Identifiable {
    let cuoc: Cuoc
    var quanhTs: Int64? = nil
    var sangMsgId: String? = nil
    var id: String { cuoc.id + (sangMsgId ?? "") + (quanhTs.map { "_\($0)" } ?? "") }
}

struct ThongTinCuocGoi: Equatable {
    let nguon: String?
    let chiTiet: String?
    let thoiGian: Date
}

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
    @Published var tabChon: Int = 0
    @Published var duongDanChat = NavigationPath()
    @Published var cuocGoiHienTai: ThongTinCuocGoi? = nil
    @Published var dangTrongCuocGoi = false
    @Published var dangXuLyCuocGoi = false
    @Published var hienTinThuHoi: Bool = UserDefaults.standard.object(forKey: "hienTinThuHoi") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(hienTinThuHoi, forKey: "hienTinThuHoi")
        }
    }
    let sse = SSEManager()
    private var huyTheoDoiThongBao: AnyCancellable?

    init() {
        let s = AppSettings()
        settings = s
        api = ZaloAPI(baseURL: s.baseURL)
        NotificationManager.shared.xinQuyen()
        BackgroundAudioManager.shared.batDauChayNen()
        ViTriGiuNen.shared.batDau()   // giữ nền DUY NHẤT bằng vị trí (tiếng tĩnh đã tắt từ v3.9)
        BaoAppDaTat.shared.batDau()   // app bị tắt -> 6s sau hiện thông báo "ZaloCall đã ngừng chạy"
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            BackgroundAudioManager.shared.batDauChayNen()
            ViTriGiuNen.shared.batDau()
        }
        huyTheoDoiThongBao = sse.suKien.receive(on: DispatchQueue.main).sink { [weak self] sk in self?.xuLyThongBaoNen(sk) }
        NotificationCenter.default.addObserver(forName: .moCuocTuThongBao, object: nil, queue: .main) { [weak self] notif in
            guard let self = self,
                  let cuocId = notif.userInfo?["cuocId"] as? String else { return }
            let msgId = notif.userInfo?["msgId"] as? String
            self.moCuocTuThongBao(cuocId: cuocId, msgId: msgId)
        }
    }

    private func xuLyThongBaoNen(_ sk: SuKienZalo) {
        switch sk {
        case .tinMoi(let cuocId, let tin, let laTinMoi):
            guard laTinMoi else { return }
            let c = dsCuocCache[cuocId]
            let ten = c?.ten ?? tin.tenNguoi ?? tin.tenCuoc ?? (cuocId == "so_tay" ? "Cloud của tôi" : "Tin nhắn Zalo")
            NotificationManager.shared.baoTinMoiNeuCan(cuocId: cuocId, tin: tin, tenCuoc: ten,
                                                        laNhom: c?.laNhomBool ?? false, daTatThongBaoNhom: c?.daTatThongBao ?? false)
        case .cuocGoiDen(let nguon, let chiTiet, let thoiGian):
            // PC (bot_zalo.mjs) chỉ phát chuông khi chính nó KHÔNG ở trong cuộc gọi -> tin PC, gỡ cờ cũ.
            // 19/10/2026: cờ dangTrongCuocGoi từng kẹt true (bốc máy trượt, lỡ tín hiệu kết thúc lúc app ở nền)
            // -> app im lặng với mọi cuộc gọi sau, kể cả khi đang mở app.
            self.dangTrongCuocGoi = false
            BackgroundAudioManager.shared.tiepTucSauCuocGoi()   // lỡ tín hiệu kết thúc cuộc trước thì gỡ ở đây
            self.cuocGoiHienTai = ThongTinCuocGoi(nguon: nguon, chiTiet: chiTiet, thoiGian: thoiGian)
            RingtoneManager.shared.batDauChuong()
            NotificationManager.shared.baoCuocGoiDen(nguon: nguon, chiTiet: chiTiet)
        case .cuocGoiDaTraLoi:
            self.cuocGoiHienTai = nil
            self.dangTrongCuocGoi = true
            RingtoneManager.shared.tatChuong()
            NotificationManager.shared.xoaBaoCuocGoi()
        case .cuocGoiKetThuc:
            self.cuocGoiHienTai = nil
            self.dangTrongCuocGoi = false
            RingtoneManager.shared.tatChuong()
            NotificationManager.shared.xoaBaoCuocGoi()
            BackgroundAudioManager.shared.tiepTucSauCuocGoi()
        default:
            break
        }
    }

    func tatChuongCucBo() {
        self.cuocGoiHienTai = nil
        self.dangTrongCuocGoi = false
        RingtoneManager.shared.tatChuong()
        NotificationManager.shared.xoaBaoCuocGoi()
    }

    func bocMayTrenPC() {
        tatChuongCucBo()
    }

    func tuChoiCuocGoi() {
        tatChuongCucBo()
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
        TinNhanDiskCache.shared.xoaToanBo()
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

    func moCuocTuThongBao(cuocId: String, msgId: String?) {
        guard !cuocId.isEmpty else { return }
        tabChon = 0
        Task {
            var cuocMucTieu = dsCuocCache[cuocId]
            if cuocMucTieu == nil {
                if let ds = try? await api.dsCuoc(), let tim = ds.first(where: { $0.id == cuocId }) {
                    cuocMucTieu = tim
                    dsCuocCache[cuocId] = tim
                } else {
                    let laNhom = cuocId.contains("@g.us") || cuocId.count > 16 ? 1 : 0
                    cuocMucTieu = Cuoc(id: cuocId, laNhom: laNhom, ten: (cuocId == "so-tay" || cuocId == "so_tay") ? "📒 Sổ tay" : cuocId,
                                       anh: nil, tinCuoiTs: nil, tinCuoi: nil, chuaDoc: 0, capNhatLuc: nil,
                                       ghim: nil, tatTb: nil)
                }
            }

            guard let cuoc = cuocMucTieu else { return }

            await MainActor.run {
                var moi = NavigationPath()
                moi.append(YeuCauMoCuoc(cuoc: cuoc, sangMsgId: msgId))
                self.duongDanChat = moi
            }
        }
    }

    /// Nhảy trực tiếp tới cuộc trò chuyện (từ Sổ tay hoặc nhắc hẹn). Pushes onto current NavigationStack.
    func moCuocHoiThoai(cuocId: String, tenCuoc: String? = nil, msgId: String? = nil, quanhTs: Int64? = nil) {
        guard !cuocId.isEmpty else { return }
        tabChon = 0
        Task {
            var cuocMucTieu = dsCuocCache[cuocId]
            if cuocMucTieu == nil {
                if let ds = try? await api.dsCuoc(), let tim = ds.first(where: { $0.id == cuocId }) {
                    cuocMucTieu = tim
                    dsCuocCache[cuocId] = tim
                } else {
                    let laNhom = cuocId.contains("@g.us") || cuocId.count > 16 ? 1 : 0
                    let ten = tenCuoc ?? ((cuocId == "so-tay" || cuocId == "so_tay") ? "📒 Sổ tay" : cuocId)
                    cuocMucTieu = Cuoc(id: cuocId, laNhom: laNhom, ten: ten,
                                       anh: nil, tinCuoiTs: nil, tinCuoi: nil, chuaDoc: 0, capNhatLuc: nil,
                                       ghim: nil, tatTb: nil)
                }
            }

            guard let cuoc = cuocMucTieu else { return }

            await MainActor.run {
                self.duongDanChat.append(YeuCauMoCuoc(cuoc: cuoc, quanhTs: quanhTs, sangMsgId: msgId))
            }
        }
    }
}
