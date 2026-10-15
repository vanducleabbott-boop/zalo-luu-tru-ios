// Thông báo cục bộ: chỉ hiện khi app đang ở NỀN mà SSE còn sống (tin mới của người khác).
// Không dùng APNs (giai đoạn 1 không yêu cầu).

import Foundation
import UserNotifications
import UIKit

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func xinQuyen() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Gọi khi nhận tin mới qua SSE. Chỉ báo khi: không phải tin của mình, app đang ở nền, nhóm chưa bị tắt thông báo.
    func baoTinMoiNeuCan(cuocId: String, tin: Tin, tenCuoc: String, laNhom: Bool, daTatThongBaoNhom: Bool) {
        guard !tin.laToi, !daTatThongBaoNhom else { return }
        guard UIApplication.shared.applicationState != .active else { return }
        let nd = UNMutableNotificationContent()
        nd.title = tenCuoc
        nd.body = xemTruoc(tin)
        nd.sound = .default
        nd.userInfo = ["cuoc": cuocId]
        let yc = UNNotificationRequest(identifier: "tin-\(tin.msgId)", content: nd, trigger: nil)
        UNUserNotificationCenter.current().add(yc)
    }

    private func xemTruoc(_ t: Tin) -> String {
        let tenGui = t.tenNguoi.map { $0 + ": " } ?? ""
        switch t.kieu {
        case "anh": return tenGui + "[Hình ảnh]"
        case "gif": return tenGui + "[GIF]"
        case "video": return tenGui + "[Video]"
        case "ghiam": return tenGui + "[Tin nhắn thoại]"
        case "sticker": return tenGui + "[Sticker]"
        case "file": return tenGui + "[File] " + (t.tenFile ?? "")
        case "lich": return tenGui + (t.chu ?? "[Lịch hẹn]")
        default: return tenGui + (t.chu ?? "")
        }
    }
}
