// Quản lý kết nối thời gian thực (thay cho `noiSuKien()`/`quayLaiTrang()` trong web/index.html):
// mở /api/su-kien, phát lại sự kiện qua Combine, tự nối lại khi im lặng quá lâu hoặc app lên foreground.

import Foundation
import Combine
import UIKit

enum SuKienZalo {
    case tinMoi(cuocId: String, tin: Tin, laTinMoi: Bool)   // "tin" (moi) hoac "sua" (sua/thu hoi/cam xuc)
    case daDoc(cuocId: String?)
    case ghimDoiThayDoi
    case tinGhimThayDoi(cuocId: String, dsGhim: [TinGhim])
    case ketNoiLai   // vua mo lai ket noi -> noi goi tai bu nhu web (taiBu())
    case cuocGoiDen(nguon: String?, chiTiet: String?, thoiGian: Date)
    case cuocGoiDaTraLoi
    case cuocGoiKetThuc
    case zaloTrangThai(ZaloServerStatus)
    case nhomTuyChonThayDoi([NhomTuyChon])
    case binhChonThayDoi(cuocId: String, pollId: String)
}

private struct PayloadTin: Decodable {
    let cuocId: String
    let tin: Tin
    enum CodingKeys: String, CodingKey { case cuocId = "cuoc_id"; case tin }
}
private struct PayloadDoc: Decodable {
    let cuocId: String?
    enum CodingKeys: String, CodingKey { case cuocId = "cuoc_id" }
}

@MainActor
final class SSEManager: ObservableObject {
    @Published private(set) var daKetNoi = false
    @Published private(set) var thongBaoTrangThai = "Chưa kết nối"
    let suKien = PassthroughSubject<SuKienZalo, Never>()

    private var client: SSEClient?
    private var lastHeard = Date.distantPast
    private var vongLap: Task<Void, Never>?
    private var taskThuLai: Task<Void, Never>?
    private var quanSatVongDoi: AnyCancellable?
    private var apiHienTai: ZaloAPI?

    func batDau(api: ZaloAPI) {
        apiHienTai = api
        taskThuLai?.cancel(); taskThuLai = nil
        dungHan(giuApi: true)
        guard let u = try? api.diaChiSuKien() else {
            thongBaoTrangThai = "Lỗi địa chỉ máy chủ"
            return
        }
        let token = api.giaTriCookiePhien()
        let clientMoi = SSEClient(url: u, token: token)
        client = clientMoi
        lastHeard = Date()
        thongBaoTrangThai = "Đang kết nối..."
        Task {
            await clientMoi.mo(
                onEvent: { [weak self] sk in Task { @MainActor in self?.xuLy(sk) } },
                onClosed: { [weak self] loi in
                    Task { @MainActor in
                        guard let self else { return }
                        self.daKetNoi = false
                        let moTa = loi?.localizedDescription ?? "Ngắt kết nối"
                        self.thongBaoTrangThai = "Mất kết nối (\(moTa))"
                        print("[SSEManager] Ket noi bi dong: \(moTa), se tu dong thu lai sau 3 giay...")
                        // Tu dong thu lai sau 3 giay neu con api
                        self.taskThuLai?.cancel()
                        self.taskThuLai = Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            if !Task.isCancelled, let curApi = self.apiHienTai {
                                self.batDau(api: curApi)
                            }
                        }
                    }
                }
            )
        }
        if vongLap == nil { vongLapKiemTra() }
        if quanSatVongDoi == nil { theoDoiVongDoiApp() }
    }

    func dungHan(giuApi: Bool = false) {
        taskThuLai?.cancel(); taskThuLai = nil
        vongLap?.cancel(); vongLap = nil
        quanSatVongDoi?.cancel(); quanSatVongDoi = nil
        let cuMa = client
        client = nil
        daKetNoi = false
        if !giuApi {
            apiHienTai = nil
            thongBaoTrangThai = "Đã ngắt kết nối"
        }
        Task { await cuMa?.dong() }
    }

    /// Gọi khi app vừa lên foreground / có mạng trở lại: nối lại nếu đã im lặng quá lâu, rồi luôn báo tải bù.
    func noiLaiNeuCan() {
        guard let api = apiHienTai else { return }
        if canReconnectSSE(lastHeard: lastHeard, now: Date()) || client == nil {
            batDau(api: api)
        }
        suKien.send(.ketNoiLai)
    }

    private func xuLy(_ sk: SuKienSSE) {
        lastHeard = Date()
        daKetNoi = true
        thongBaoTrangThai = "Đang kết nối realtime"
        switch sk.loai {
        case "tin", "sua":
            guard let data = sk.data.data(using: .utf8) else { return }
            do {
                let p = try JSONDecoder().decode(PayloadTin.self, from: data)
                print("[SSE] Nhan tin moi thanh cong cho cuoc:", p.cuocId, "msgId:", p.tin.msgId)
                suKien.send(.tinMoi(cuocId: p.cuocId, tin: p.tin, laTinMoi: sk.loai == "tin"))
            } catch {
                print("[SSE] Loi giai ma PayloadTin:", error.localizedDescription)
            }
        case "doc":
            let p = sk.data.data(using: .utf8).flatMap { try? JSONDecoder().decode(PayloadDoc.self, from: $0) }
            suKien.send(.daDoc(cuocId: p?.cuocId))
        case "ghim":
            suKien.send(.ghimDoiThayDoi)
        case "tin_ghim":
            guard let data = sk.data.data(using: .utf8) else { return }
            struct PayloadGhim: Decodable {
                let cuocId: String
                let dsGhim: [TinGhim]
            }
            if let p = try? JSONDecoder().decode(PayloadGhim.self, from: data) {
                suKien.send(.tinGhimThayDoi(cuocId: p.cuocId, dsGhim: p.dsGhim))
            }
        case "lich":
            suKien.send(.ketNoiLai)
        case "cuoc-goi", "goi":
            guard let data = sk.data.data(using: .utf8) else { return }
            struct PayloadGoi: Decodable {
                let loai: String?
                let tu: String?
                let nguon: String?
                let chiTiet: String?
            }
            if let p = try? JSONDecoder().decode(PayloadGoi.self, from: data) {
                let laBatDau = (p.loai == "goi-den" || p.loai == "chuong-bat-dau")
                let laDaTraLoi = (p.loai == "da-tra-loi")
                let laKetThuc = (p.loai == "ket-thuc" || p.loai == "chuong-ket-thuc" || p.loai == "da-tu-choi" || p.loai == "ngat")
                if laBatDau {
                    print("[SSE] PHAT HIEN CUOC GOI DEN tu:", p.nguon ?? p.tu ?? "Zalo PC")
                    suKien.send(.cuocGoiDen(nguon: p.nguon ?? p.tu, chiTiet: p.chiTiet, thoiGian: Date()))
                } else if laDaTraLoi {
                    print("[SSE] CUOC GOI DA DUOC TRA LOI")
                    suKien.send(.cuocGoiDaTraLoi)
                } else if laKetThuc {
                    print("[SSE] CUOC GOI KET THUC")
                    suKien.send(.cuocGoiKetThuc)
                }
            }
        case "zalo_trang_thai":
            guard let data = sk.data.data(using: .utf8) else { return }
            if let p = try? JSONDecoder().decode(ZaloServerStatus.self, from: data) {
                print("[SSE] Zalo server status:", p.trangThai, "daDangNhap:", p.daDangNhap)
                suKien.send(.zaloTrangThai(p))
            }
        case "nhom_tuy_chon":
            guard let data = sk.data.data(using: .utf8) else { return }
            if let ds = try? JSONDecoder().decode([NhomTuyChon].self, from: data) {
                print("[SSE] Nhan nhom tuy chon moi tu server:", ds.count)
                suKien.send(.nhomTuyChonThayDoi(ds))
            }
        case "binh_chon":
            guard let data = sk.data.data(using: .utf8) else { return }
            struct PayloadBC: Decodable {
                let cuocId: String?
                let pollId: String?
            }
            if let p = try? JSONDecoder().decode(PayloadBC.self, from: data) {
                suKien.send(.binhChonThayDoi(cuocId: p.cuocId ?? "", pollId: p.pollId ?? ""))
            }
        default:
            break   // "nhip" chi de cap nhat lastHeard
        }
    }

    // Giống setInterval 5s của web: định kỳ kiểm tra im lặng quá 40s thì tự nối lại.
    private func vongLapKiemTra() {
        vongLap = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self else { continue }
                // 19/10/2026: chạy cả khi app ở nền (app được giữ sống bằng tiếng tĩnh) - trước chỉ chạy khi app
                // trên màn hình nên SSE chết lúc ở nền là mất chuông tới khi mở app. Kèm đảm bảo tiếng tĩnh còn phát.
                BackgroundAudioManager.shared.batDauChayNen()
                if canReconnectSSE(lastHeard: self.lastHeard, now: Date()) { self.noiLaiNeuCan() }
            }
        }
    }

    private func theoDoiVongDoiApp() {
        quanSatVongDoi = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.noiLaiNeuCan() }
    }
}
