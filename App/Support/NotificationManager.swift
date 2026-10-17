// Thông báo cục bộ: chỉ hiện khi app đang ở NỀN mà SSE còn sống (tin mới của người khác).
// Không dùng APNs (giai đoạn 1 không yêu cầu).

import Foundation
import UserNotifications
import UIKit

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func xinQuyen(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { chapNhan, loi in
            print("[Notification] Xin quyen:", chapNhan, loi?.localizedDescription ?? "")
            DispatchQueue.main.async {
                completion?(chapNhan)
            }
        }
    }

    func kiemTraQuyen(completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus)
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    /// Gọi khi nhận tin mới qua SSE. Chỉ báo khi: không phải tin của mình và nhóm chưa bị tắt thông báo.
    /// Cho phép thông báo cả khi app đang mở hoặc đang chạy nền.
    func baoTinMoiNeuCan(cuocId: String, tin: Tin, tenCuoc: String, laNhom: Bool, daTatThongBaoNhom: Bool) {
        guard !tin.laToi, !daTatThongBaoNhom else {
            print("[Notification] Bo qua tin: laToi=\(tin.laToi), daTatTb=\(daTatThongBaoNhom)")
            return
        }
        let nd = UNMutableNotificationContent()
        nd.title = tenCuoc
        nd.body = xemTruoc(tin)
        nd.sound = .default
        nd.userInfo = ["cuoc": cuocId]
        let yc = UNNotificationRequest(identifier: "tin-\(tin.msgId)", content: nd, trigger: nil)
        UNUserNotificationCenter.current().add(yc) { loi in
            if let loi {
                print("[Notification] Loi hien thong bao tin moi:", loi.localizedDescription)
            } else {
                print("[Notification] Da them thong bao tin moi:", tin.msgId, "tu:", tenCuoc)
            }
        }
    }

    func guiThongBaoThu() {
        let nd = UNMutableNotificationContent()
        nd.title = "Thông báo thử nghiệm"
        nd.body = "Hệ thống thông báo của Zalo lưu trữ đang hoạt động tốt!"
        nd.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let yc = UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: nd, trigger: trigger)
        UNUserNotificationCenter.current().add(yc) { loi in
            if let loi {
                print("[Notification] Loi gui thong bao thu:", loi.localizedDescription)
            }
        }
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
