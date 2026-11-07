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
    /// Lỗi xảy ra khi chat không mở -> lần mở sau báo.
    private var loiChuaXem: [String: String] = [:]
    let ketThuc = PassthroughSubject<KetThuc, Never>()
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
    func layLoiChuaXem(_ cuocId: String) -> String? { loiChuaXem.removeValue(forKey: cuocId) }

    /// Chạy 1 việc tải (1 tệp hoặc 1 album). `xongMot(id)` tắt vòng xoay của 1 ô khi ô đó đã lên máy chủ.
    func chay(cuocId: String, tin: [Tin], laAlbum: Bool,
              viec: @escaping @MainActor (_ xongMot: @escaping @MainActor (String) -> Void) async throws -> Void) {
        let ids = tin.map(\.msgId)
        tinTam[cuocId, default: []] += tin
        dangTaiLen.formUnion(ids)
        Task { @MainActor in
            let nen = GiuChayNen(ten: "ZaloTaiLen")
            defer { nen.ket() }
            var loi: String?
            do {
                try await viec { [weak self] id in _ = self?.dangTaiLen.remove(id) }
            } catch {
                loi = error.localizedDescription
            }
            dangTaiLen.subtract(ids)
            tinTam[cuocId]?.removeAll { ids.contains($0.msgId) }
            if tinTam[cuocId]?.isEmpty == true { tinTam[cuocId] = nil }
            if let loi { loiChuaXem[cuocId] = (laAlbum ? "Không gửi được album: " : "Không gửi được tệp: ") + loi }
            ketThuc.send(KetThuc(cuocId: cuocId, ids: ids, loi: loi, laAlbum: laAlbum))
        }
    }

    /// Chờ tới khi app không còn ở nền (iOS treo app thì Task cũng dừng; vào lại app thì chạy tiếp từ đây).
    func choVaoLaiApp() async {
        while UIApplication.shared.applicationState == .background {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    /// Tải 1 tệp lên chỗ chờ của máy chủ (album). Mạng chập chờn: thử lại 2 lần; hỏng vì app bị treo ở nền:
    /// chờ vào lại app rồi thử tiếp (tối đa 8 lần). Tải lên chỗ chờ không gửi gì sang Zalo nên thử lại an toàn.
    func taiLenCoThuLai(_ env: AppEnvironment, _ duLieu: Data, tenFile: String) async throws -> String {
        var lan = 0
        while true {
            let nenTruoc = soLanVaoNen
            do { return try await env.api.taiLenTam(duLieu: duLieu, tenFile: tenFile) }
            catch let e as URLError where e.code != .cancelled && lan < 8 && (lan < 2 || soLanVaoNen != nenTruoc) {
                lan += 1
                await choVaoLaiApp()
                env.api.lamMoiKetNoiTaiLen()   // thử lại trên kết nối mới
                try await Task.sleep(nanoseconds: UInt64(min(lan, 3)) * 1_500_000_000)
            }
        }
    }

    /// Gửi thẳng 1 tệp. Chỉ thử lại khi hỏng do app bị treo ở nền (lỗi mạng thường có thể máy chủ đã gửi rồi -> không gửi lặp).
    func guiFileCoThuLai(_ env: AppEnvironment, cuocId: String, duLieu: Data, tenFile: String, trich: String?) async throws {
        var lan = 0
        while true {
            let nenTruoc = soLanVaoNen
            do { try await env.api.guiFile(cuoc: cuocId, duLieu: duLieu, tenFile: tenFile, trichMsgId: trich); return }
            catch let e as URLError where e.code != .cancelled && lan < 5 && soLanVaoNen != nenTruoc {
                lan += 1
                await choVaoLaiApp()
                env.api.lamMoiKetNoiTaiLen()
                try await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }
}

/// Xin iOS cho app chạy thêm khi đã thoát ra ngoài (khoảng 30 giây) để tải xong; hết giờ thì trả lại cho iOS.
final class GiuChayNen {
    private var id: UIBackgroundTaskIdentifier = .invalid

    @MainActor init(ten: String) {
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
