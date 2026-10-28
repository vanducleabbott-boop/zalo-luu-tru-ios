// Địa chỉ máy chủ (Tailscale HTTPS) - lưu trong UserDefaults, sửa được ở màn Cài đặt.

import Foundation
import Combine

final class AppSettings: ObservableObject {
    static let diaChiMacDinh = "https://zalo.nhaduc.name.vn"
    private static let khoaLuu = "zl_dia_chi_may_chu"

    @Published var diaChiMayChu: String {
        didSet { UserDefaults.standard.set(diaChiMayChu, forKey: Self.khoaLuu) }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.khoaLuu) {
            let trimmed = saved.trimmingCharacters(in: .whitespacesAndNewlines)
            var normalized = trimmed
            while normalized.hasSuffix("/") {
                normalized.removeLast()
            }
            if normalized == "https://desktop-krdjkc2.tailbd558a.ts.net:8443" {
                diaChiMayChu = Self.diaChiMacDinh
                UserDefaults.standard.set(Self.diaChiMacDinh, forKey: Self.khoaLuu)
            } else {
                diaChiMayChu = saved
            }
        } else {
            diaChiMayChu = Self.diaChiMacDinh
        }
    }

    var baseURL: URL {
        URL(string: diaChiMayChu) ?? URL(string: Self.diaChiMacDinh)!
    }
}
