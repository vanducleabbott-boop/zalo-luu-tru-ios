// Giữ app chạy nền bằng chế độ theo dõi vị trí (UIBackgroundModes: location) - cách Apple cho phép chính thức,
// không bị YouTube/nhạc/cuộc gọi thật làm gián đoạn như tiếng tĩnh (BackgroundAudioManager vẫn giữ làm lớp phụ).
// Độ chính xác thấp nhất (~3 km, sóng di động/Wi-Fi, không bật GPS) + distanceFilter tối đa để đỡ pin.
// Vị trí KHÔNG dùng, KHÔNG gửi đi đâu - chỉ cần luồng cập nhật vị trí còn chạy là iOS không treo app. (19/10/2026)

import Foundation
import CoreLocation

final class ViTriGiuNen: NSObject, CLLocationManagerDelegate {
    static let shared = ViTriGiuNen()
    private let quanLy = CLLocationManager()
    private var dangChay = false

    private override init() {
        super.init()
        quanLy.delegate = self
        quanLy.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        quanLy.distanceFilter = CLLocationDistanceMax
        quanLy.pausesLocationUpdatesAutomatically = false   // để mặc định thì iOS tự dừng khi máy đứng yên -> app bị treo
        quanLy.activityType = .other
    }

    func batDau() {
        switch quanLy.authorizationStatus {
        case .notDetermined:
            quanLy.requestAlwaysAuthorization()   // cập nhật tiếp ở locationManagerDidChangeAuthorization
        case .authorizedAlways, .authorizedWhenInUse:
            chay()
        default:
            print("[ViTriGiuNen] Chua cap quyen vi tri - chi con tieng tinh giu nen")
        }
    }

    private func chay() {
        // allowsBackgroundLocationUpdates chỉ đặt được khi Info.plist có UIBackgroundModes location (đã khai trong project.yml)
        quanLy.allowsBackgroundLocationUpdates = true
        quanLy.showsBackgroundLocationIndicator = true
        quanLy.startUpdatingLocation()
        if !dangChay { print("[ViTriGiuNen] Da bat theo doi vi tri giu nen") }
        dangChay = true
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: chay()
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[ViTriGiuNen] Loi vi tri (van giu luong cap nhat):", error.localizedDescription)
    }
}
