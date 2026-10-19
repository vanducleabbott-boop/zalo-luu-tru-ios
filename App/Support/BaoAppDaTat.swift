// Báo khi app bị tắt (vuốt khỏi đa nhiệm / iOS dừng) - mẹo của app Clip (rileytestut/Clip ApplicationMonitor.swift):
// cứ 5s hẹn 1 thông báo cục bộ sau 6s, CÙNG mã định danh -> hẹn mới thay hẹn cũ nên khi app còn sống thông báo
// không bao giờ kịp hiện. App chết thì không còn ai hẹn lại -> 6s sau thông báo hiện, chạm vào là mở lại app.
// (19/10/2026, v4.0)

import Foundation
import UserNotifications

final class BaoAppDaTat {
    static let shared = BaoAppDaTat()
    private let maThongBao = "zalocall.app-da-ngung-chay"
    private let chuKy: TimeInterval = 5
    private var dangChay = false

    private init() {}

    func batDau() {
        guard !dangChay else { return }
        dangChay = true
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [maThongBao])
        henLai()
    }

    private func henLai() {
        let nd = UNMutableNotificationContent()
        nd.title = "ZaloCall đã ngừng chạy"
        nd.body = "Chạm để mở lại, nếu không sẽ không nhận được cuộc gọi Zalo."
        nd.sound = .default
        let kichHoat = UNTimeIntervalNotificationTrigger(timeInterval: chuKy + 1, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: maThongBao, content: nd, trigger: kichHoat))
        DispatchQueue.global().asyncAfter(deadline: .now() + chuKy) { [weak self] in self?.henLai() }
    }
}
