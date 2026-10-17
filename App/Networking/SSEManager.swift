// Quản lý kết nối thời gian thực (thay cho `noiSuKien()`/`quayLaiTrang()` trong web/index.html):
// mở /api/su-kien, phát lại sự kiện qua Combine, tự nối lại khi im lặng quá lâu hoặc app lên foreground.

import Foundation
import Combine
import UIKit

enum SuKienZalo {
    case tinMoi(cuocId: String, tin: Tin, laTinMoi: Bool)   // "tin" (moi) hoac "sua" (sua/thu hoi/cam xuc)
    case daDoc(cuocId: String?)
    case ghimDoiThayDoi
    case ketNoiLai   // vua mo lai ket noi -> noi goi tai bu nhu web (taiBu())
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
    let suKien = PassthroughSubject<SuKienZalo, Never>()

    private var client: SSEClient?
    private var lastHeard = Date.distantPast
    private var vongLap: Task<Void, Never>?
    private var quanSatVongDoi: AnyCancellable?
    private var apiHienTai: ZaloAPI?

    func batDau(api: ZaloAPI) {
        apiHienTai = api
        dungHan(giuApi: true)
        guard let u = try? api.diaChiSuKien() else { return }
        let clientMoi = SSEClient(url: u)
        client = clientMoi
        lastHeard = Date()
        Task {
            await clientMoi.mo(
                onEvent: { [weak self] sk in Task { @MainActor in self?.xuLy(sk) } },
                onClosed: { [weak self] _ in Task { @MainActor in self?.daKetNoi = false } }
            )
        }
        if vongLap == nil { vongLapKiemTra() }
        if quanSatVongDoi == nil { theoDoiVongDoiApp() }
    }

    func dungHan(giuApi: Bool = false) {
        vongLap?.cancel(); vongLap = nil
        quanSatVongDoi?.cancel(); quanSatVongDoi = nil
        let cuMa = client
        client = nil
        daKetNoi = false
        if !giuApi { apiHienTai = nil }
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
        default:
            break   // "nhip" chi de cap nhat lastHeard; "goi" (cuoc goi WebRTC) la giai doan 2, chua xu ly
        }
    }

    // Giống setInterval 5s của web: định kỳ kiểm tra im lặng quá 40s thì tự nối lại.
    private func vongLapKiemTra() {
        vongLap = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, UIApplication.shared.applicationState == .active else { continue }
                if canReconnectSSE(lastHeard: self.lastHeard, now: Date()) { self.noiLaiNeuCan() }
            }
        }
    }

    private func theoDoiVongDoiApp() {
        quanSatVongDoi = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.noiLaiNeuCan() }
    }
}
