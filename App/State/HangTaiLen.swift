// v8.1 (07/11/2026): hàng tải lên toàn cục - tải ảnh/video KHÔNG gắn với màn hình chat.
// Trước: tin tạm + vòng xoay nằm trong ChatViewModel -> rời chat (về trang chủ) rồi vào lại là mất ô đang tải;
// thoát app thì iOS treo app -> đứt kết nối -> báo lỗi, xoá ô. Giờ:
// - Việc tải chạy trong Task riêng, giữ tin tạm theo cuộc -> mở lại chat vẫn thấy ô đang tải (vòng xoay).
// - Xin iOS chạy nền (beginBackgroundTask, ~30s) khi thoát app; bị treo giữa chừng thì vào lại app tự tải tiếp.

import Foundation
import Combine
import UIKit

@MainActor
final class HangTaiLen: ObservableObject {
    static let shared = HangTaiLen()

    struct KetThuc {
        let cuocId: String
        let ids: [String]
        let loi: String?
        let laAlbum: Bool
    }

    /// msgId tạm đang tải -> ô ảnh hiện vòng xoay.
    @Published private(set) var dangTaiLen: Set<String> = []
    /// Tin tạm của các việc chưa xong, theo cuộc (mở lại chat thì gộp vào khung chat).
    private(set) var tinTam: [String: [Tin]] = [:]
    /// v8.3: msgId tạm của các việc còn đang chạy (khác dangTaiLen: ô đã lên máy chủ nhưng việc chưa xong vẫn tính).
    private(set) var dangChay: Set<String> = []
    /// Lỗi xảy ra khi chat không mở -> lần mở sau báo.
    private var loiChuaXem: [String: String] = [:]
    let ketThuc = PassthroughSubject<KetThuc, Never>()
    /// v8.3: ô tạm đã có tệp thật (đổi định dạng xong) -> chat đang mở thay ô (cuocId, tin mới cùng msgId).
    let capNhatTin = PassthroughSubject<(String, Tin), Never>()
    /// v8.3: bỏ ô tạm (mục trong album không đọc được) -> (cuocId, msgId).
    let xoaTin = PassthroughSubject<(String, String), Never>()
    /// Tăng mỗi lần app vào nền -> biết 1 lần tải hỏng là do iOS treo app (thì vào lại app tải tiếp).
    private(set) var soLanVaoNen = 0
    private var quanSat: NSObjectProtocol?

    private init() {
        quanSat = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                         object: nil, queue: .main) { _ in
            Task { @MainActor in HangTaiLen.shared.soLanVaoNen += 1 }
        }
    }

    func tinTamCua(_ cuocId: String) -> [Tin] { tinTam[cuocId] ?? [] }
    /// Tin thật đã về (SSE) -> bỏ ô tạm khỏi danh sách để lần nạp lại không hiện trùng.
    func boTinTam(cuocId: String, msgId: String) {
        tinTam[cuocId]?.removeAll { $0.msgId == msgId }
        if tinTam[cuocId]?.isEmpty == true { tinTam[cuocId] = nil }
    }
    /// v8.3: thay ô tạm (cùng msgId) bằng bản đã có tệp xem trước.
    func thayTinTam(cuocId: String, tin: Tin) {
        if let i = tinTam[cuocId]?.firstIndex(where: { $0.msgId == tin.msgId }) { tinTam[cuocId]?[i] = tin }
        capNhatTin.send((cuocId, tin))
    }
    /// v8.3: bỏ hẳn 1 ô tạm (không đọc được tệp) - tắt vòng xoay + xoá khỏi chat.
    func boOTam(cuocId: String, msgId: String) {
        boTinTam(cuocId: cuocId, msgId: msgId)
        dangTaiLen.remove(msgId)
        xoaTin.send((cuocId, msgId))
    }
    func layLoiChuaXem(_ cuocId: String) -> String? { loiChuaXem.removeValue(forKey: cuocId) }

    /// Chạy 1 việc tải (1 tệp hoặc 1 album). `xongMot(id)` tắt vòng xoay của 1 ô khi ô đó đã lên máy chủ.
    func chay(cuocId: String, tin: [Tin], laAlbum: Bool,
              viec: @escaping @MainActor (_ xongMot: @escaping @MainActor (String) -> Void) async throws -> Void) {
        let ids = tin.map(\.msgId)
        tinTam[cuocId, default: []] += tin
        dangTaiLen.formUnion(ids)
        dangChay.formUnion(ids)
        Task { @MainActor [self] in
            let nen = GiuChayNen(ten: "ZaloTaiLen")
            defer { nen.ket() }
            var loi: String?
            do {
                try await viec { [weak self] id in _ = self?.dangTaiLen.remove(id) }
            } catch {
                loi = error.localizedDescription
            }
            dangTaiLen.subtract(ids)
            dangChay.subtract(ids)
            if loi != nil {
                tinTam[cuocId]?.removeAll { ids.contains($0.msgId) }
                if tinTam[cuocId]?.isEmpty == true { tinTam[cuocId] = nil }
            } else {
                // v8.3: việc OK nhưng máy chủ gửi Zalo chạy nền (có thể >100s) -> GIỮ ô tạm tới khi tin thật khớp (SSE/đồng bộ);
                // quá 180s mà còn thì bỏ.
                Task { @MainActor [self] in
                    try? await Task.sleep(nanoseconds: 180 * 1_000_000_000)
                    for id in ids where tinTam[cuocId]?.contains(where: { $0.msgId == id }) == true {
                        boOTam(cuocId: cuocId, msgId: id)
                    }
                }
            }
            if let loi { loiChuaXem[cuocId] = (laAlbum ? "Không gửi được album: " : "Không gửi được tệp: ") + loi }
            ketThuc.send(KetThuc(cuocId: cuocId, ids: ids, loi: loi, laAlbum: laAlbum))
        }
    }

    /// Chờ tới khi app không còn ở nền (iOS treo app thì Task cũng dừng; vào lại app thì chạy tiếp từ đây).
    func choVaoLaiApp() async {
        while UIApplication.shared.applicationState == .background {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    /// v8.3: lỗi tạm thời (mất sóng, app bị treo ở nền, máy chủ/Cloudflare tạm không tới được) -> thử lại tới khi được:
    /// chờ app vào lại, mở kết nối mới, giãn cách tăng dần tối đa 20s. Trần: hết giờ (timedOut) quá 15 lần hoặc tổng > 45 phút -> ném lỗi.
    /// Lỗi 4xx khác (400, 413...) thử 2 lần; lỗi khác thử 5 lần.
    func thuLaiMai<T>(_ env: AppEnvironment, _ lam: () async throws -> T) async throws -> T {
        var lanMang = 0, lanMayChu = 0, lanTu = 0, lanHetGio = 0
        let batDau = Date()
        while true {
            do { return try await lam() }
            catch is CancellationError {
                throw CancellationError()
            } catch {
                if let e = error as? URLError, e.code != .cancelled {
                    lanMang += 1
                    if e.code == .timedOut {
                        lanHetGio += 1
                        if lanHetGio > 15 { throw error }
                    }
                } else if let e = error as? LoiZaloAPI {
                    switch e {
                    case .canDangNhapCloudflare, .chuaDangNhap:
                        lanMang += 1
                    case .maHttp(let ma, _):
                        if ma >= 500 || ma == 408 || ma == 429 {
                            lanMang += 1
                        } else if ma >= 400 && ma < 500 {
                            lanTu += 1
                            if lanTu >= 2 { throw error }
                        } else {
                            lanMayChu += 1
                            if lanMayChu >= 5 { throw error }
                        }
                    case .diaChiKhongHopLe:
                        lanMayChu += 1
                        if lanMayChu >= 5 { throw error }
                    }
                } else {
                    lanMayChu += 1
                    if lanMayChu >= 5 { throw error }
                }
                if Date().timeIntervalSince(batDau) > 45 * 60 { throw error }
            }
            await choVaoLaiApp()
            env.api.lamMoiKetNoiTaiLen()   // thử lại trên kết nối mới
            let giay = UInt64(min(max(lanMang, lanMayChu, lanTu) * 2, 20))
            try await Task.sleep(nanoseconds: giay * 1_000_000_000)
        }
    }

    /// Tải 1 tệp lên chỗ chờ của máy chủ (album). Không gửi gì sang Zalo nên thử lại an toàn.
    func taiLenCoThuLai(_ env: AppEnvironment, _ duLieu: Data, tenFile: String) async throws -> String {
        try await thuLaiMai(env) { try await env.api.taiLenTam(duLieu: duLieu, tenFile: tenFile) }
    }

    /// Gửi thẳng 1 tệp. Máy chủ trả lời NGAY khi nhận đủ tệp (gửi Zalo chạy nền) -> hỏng giữa chừng gần như chắc chắn
    /// là chưa nhận đủ, thử lại không lo gửi trùng.
    func guiFileCoThuLai(_ env: AppEnvironment, cuocId: String, duLieu: Data, tenFile: String, trich: String?) async throws {
        try await thuLaiMai(env) { try await env.api.guiFile(cuoc: cuocId, duLieu: duLieu, tenFile: tenFile, trichMsgId: trich) }
    }
}

/// Xin iOS cho app chạy thêm khi đã thoát ra ngoài (khoảng 30 giây) để tải xong; hết giờ thì trả lại cho iOS.
@MainActor
final class GiuChayNen {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(ten: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: ten) { [weak self] in
            self?.ket()   // iOS gọi trên luồng chính, phải kết thúc ngay
        }
    }

    func ket() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
