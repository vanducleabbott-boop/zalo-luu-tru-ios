// Bảng màu khớp :root / [data-theme] trong web/index.html (sáng/tối theo hệ thống).

import SwiftUI
import UIKit

enum ZaloMau {
    static func thich(_ sang: UIColor, _ toi: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? toi : sang })
    }

    static let xanh = thich(UIColor(red: 0, green: 0.408, blue: 1, alpha: 1), UIColor(red: 0.239, green: 0.545, blue: 1, alpha: 1))
    /// Bong bóng tin của mình
    static let bongToi = thich(UIColor(red: 0.898, green: 0.937, blue: 1, alpha: 1), UIColor(red: 0.106, green: 0.184, blue: 0.302, alpha: 1))
    /// Bong bóng tin của người khác
    static let bongHo = thich(.white, UIColor(red: 0.165, green: 0.173, blue: 0.192, alpha: 1))
    static let nenChat = thich(UIColor(red: 0.886, green: 0.914, blue: 0.945, alpha: 1), UIColor(red: 0.078, green: 0.082, blue: 0.094, alpha: 1))
    static let chuPhu = thich(UIColor(red: 0.459, green: 0.537, blue: 0.639, alpha: 1), UIColor(red: 0.561, green: 0.6, blue: 0.651, alpha: 1))
    static let do = thich(UIColor(red: 0.91, green: 0.263, blue: 0.247, alpha: 1), UIColor(red: 1, green: 0.353, blue: 0.322, alpha: 1))
}
