// Địa chỉ máy chủ (Tailscale HTTPS) - lưu trong UserDefaults, sửa được ở màn Cài đặt.

import Foundation
import Combine

final class AppSettings: ObservableObject {
    static let diaChiMacDinh = "https://desktop-krdjkc2.tailbd558a.ts.net:8443"
    private static let khoaLuu = "zl_dia_chi_may_chu"

    @Published var diaChiMayChu: String {
        didSet { UserDefaults.standard.set(diaChiMayChu, forKey: Self.khoaLuu) }
    }

    init() {
        diaChiMayChu = UserDefaults.standard.string(forKey: Self.khoaLuu) ?? Self.diaChiMacDinh
    }

    var baseURL: URL {
        URL(string: diaChiMayChu) ?? URL(string: Self.diaChiMacDinh)!
    }
}
