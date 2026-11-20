import SwiftUI

/// Các mốc tắt thông báo 1 cuộc, giống Zalo: 1 giờ, 4 giờ, đến 8 giờ sáng, đến khi bật lại.
enum MocTatThongBao: CaseIterable, Identifiable {
    case motGio, bonGio, den8hSang, denKhiBatLai

    var id: Self { self }

    var nhan: String {
        switch self {
        case .motGio: "Trong 1 giờ"
        case .bonGio: "Trong 4 giờ"
        case .den8hSang: "Đến 8 giờ sáng"
        case .denKhiBatLai: "Đến khi bật lại"
        }
    }

    /// ms hết hạn gửi cho máy chủ; nil = không hẹn giờ.
    func den(tu bayGio: Date = Date()) -> Int64? {
        let ngay: Date?
        switch self {
        case .motGio: ngay = bayGio.addingTimeInterval(3600)
        case .bonGio: ngay = bayGio.addingTimeInterval(4 * 3600)
        case .den8hSang:
            let lich = Calendar.current
            let tamGio = lich.date(bySettingHour: 8, minute: 0, second: 0, of: bayGio) ?? bayGio
            ngay = tamGio > bayGio ? tamGio : lich.date(byAdding: .day, value: 1, to: tamGio)
        case .denKhiBatLai: ngay = nil
        }
        return ngay.map { Int64($0.timeIntervalSince1970 * 1000) }
    }
}

extension Cuoc {
    /// "đến 14:30", "đến 08:00 21/11" hoặc "đến khi bật lại"; rỗng khi đang bật thông báo.
    var ghiChuTatThongBao: String {
        guard daTatThongBao else { return "" }
        guard let tatDen else { return "đến khi bật lại" }
        let d = Date(timeIntervalSince1970: Double(tatDen) / 1000)
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "HH:mm d/M"
        return "đến " + f.string(from: d)
    }

    /// Sổ tay không có thông báo Zalo nên không cho tắt.
    var tatThongBaoDuoc: Bool { id != "so-tay" }
}

/// Nội dung menu tắt/bật thông báo dùng chung cho ⋯ trong chat và giữ lâu ở danh sách.
struct MenuTatThongBao: View {
    let cuoc: Cuoc
    let dat: (_ tat: Bool, _ den: Int64?) -> Void

    var body: some View {
        if cuoc.daTatThongBao {
            Button { dat(false, nil) } label: {
                Label("Bật lại thông báo (\(cuoc.ghiChuTatThongBao))", systemImage: "bell")
            }
        } else {
            Menu {
                ForEach(MocTatThongBao.allCases) { moc in
                    Button(moc.nhan) { dat(true, moc.den()) }
                }
            } label: {
                Label("Tắt thông báo", systemImage: "bell.slash")
            }
        }
    }
}
