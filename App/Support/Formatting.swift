// Hàm thuần, không phụ thuộc UI/mạng - test được trực tiếp. Khớp cách web/index.html hiển thị
// (gioNgan/gioPhut/ngayDai, cungNguoi/dauNhom, ganTin, kichCo...).

import Foundation

enum DinhDang {
    static func s2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    /// Giờ ngắn trong danh sách hội thoại: hôm nay = giờ:phút, hôm qua = "Hôm qua", còn lại = ngày/tháng(/năm).
    static func gioNgan(_ ts: Int64, bayGio: Date = Date()) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ts) / 1000)
        let cal = Calendar.current
        if cal.isDate(d, inSameDayAs: bayGio) {
            let c = cal.dateComponents([.hour, .minute], from: d)
            return "\(s2(c.hour ?? 0)):\(s2(c.minute ?? 0))"
        }
        if let homQua = cal.date(byAdding: .day, value: -1, to: bayGio), cal.isDate(d, inSameDayAs: homQua) { return "Hôm qua" }
        let c = cal.dateComponents([.day, .month, .year], from: d)
        let cNow = cal.dateComponents([.year], from: bayGio)
        if c.year == cNow.year { return "\(s2(c.day ?? 1))/\(s2(c.month ?? 1))" }
        return "\(s2(c.day ?? 1))/\(s2(c.month ?? 1))/\(String(c.year ?? 0).suffix(2))"
    }

    static func gioPhut(_ ts: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ts) / 1000)
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return "\(s2(c.hour ?? 0)):\(s2(c.minute ?? 0))"
    }

    private static let tenThu = ["Chủ nhật", "Thứ 2", "Thứ 3", "Thứ 4", "Thứ 5", "Thứ 6", "Thứ 7"]

    /// Mốc ngày trong khung chat: "Hôm nay" / "Hôm qua" / "Thứ X, dd/mm/yyyy".
    static func ngayDai(_ ts: Int64, bayGio: Date = Date()) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ts) / 1000)
        let cal = Calendar.current
        if cal.isDate(d, inSameDayAs: bayGio) { return "Hôm nay" }
        if let homQua = cal.date(byAdding: .day, value: -1, to: bayGio), cal.isDate(d, inSameDayAs: homQua) { return "Hôm qua" }
        let c = cal.dateComponents([.day, .month, .year, .weekday], from: d)
        let thu = tenThu[(c.weekday ?? 1) - 1]
        return "\(thu), \(s2(c.day ?? 1))/\(s2(c.month ?? 1))/\(c.year ?? 0)"
    }

    static func kichCo(_ n: Int64?) -> String {
        guard let n, n > 0 else { return "" }
        if n > 1_048_576 { return String(format: "%.1f MB", Double(n) / 1_048_576) }
        return "\(Int(ceil(Double(n) / 1024))) KB"
    }

    static func duoiFile(_ ten: String?) -> String {
        guard var ten, !ten.isEmpty else { return "" }
        if ten.lowercased().hasSuffix(".tai") {
            ten = String(ten.dropLast(4))
        }
        guard let dau = ten.lastIndex(of: ".") else { return "" }
        return String(ten[ten.index(after: dau)...]).lowercased()
    }

    /// Tên hiển thị sạch cho người dùng (bỏ đuôi tạm .tai nếu có)
    static func tenHienThiFile(_ ten: String?) -> String {
        guard var ten, !ten.isEmpty else { return "Tệp tin" }
        if ten.lowercased().hasSuffix(".tai") {
            ten = String(ten.dropLast(4))
        }
        return ten
    }

    /// Tên loại tài liệu hiển thị
    static func tenLoaiTaiLieu(_ duoi: String) -> String {
        switch duoi.uppercased() {
        case "DOC", "DOCX": return "Microsoft Word"
        case "XLS", "XLSX", "CSV": return "Microsoft Excel"
        case "PPT", "PPTX": return "Microsoft PowerPoint"
        case "PDF": return "Tài liệu PDF"
        case "ZIP", "RAR", "7Z": return "Tệp nén"
        case "TXT", "RTF": return "Văn bản"
        default: return "Tệp tin"
        }
    }
}

enum GomNhom {
    /// Khớp `cungNguoi` trong web: cùng người gửi, cùng là mình/không, và cách nhau dưới 5 phút.
    static func cungNhom(hienTai: Tin, truoc: Tin?) -> Bool {
        guard let truoc else { return false }
        return truoc.uid == hienTai.uid && truoc.laToi == hienTai.laToi && (hienTai.ts - truoc.ts) < 5 * 60_000
    }

    /// Khớp `cuoiNhom`: tin cuối trong 1 cụm (để hiện giờ + avatar) - nhìn tin kế tiếp.
    static func cuoiNhom(hienTai: Tin, sau: Tin?, bayGio: Date = Date()) -> Bool {
        guard let sau else { return true }
        if sau.uid != hienTai.uid || sau.laToi != hienTai.laToi || (sau.ts - hienTai.ts) >= 5 * 60_000 { return true }
        let cal = Calendar.current
        let dHienTai = Date(timeIntervalSince1970: TimeInterval(hienTai.ts) / 1000)
        let dSau = Date(timeIntervalSince1970: TimeInterval(sau.ts) / 1000)
        return !cal.isDate(dHienTai, inSameDayAs: dSau)
    }

    /// Gộp tin thành từng mục hiển thị kèm mốc ngày (danh sách phẳng cu -> moi, chèn divider khi đổi ngày).
    enum MucHienThi: Equatable {
        case ngay(String)
        case tin(Tin, dauNhom: Bool, cuoiNhom: Bool)
        case album([Tin], dauNhom: Bool, cuoiNhom: Bool)   // v4.3: nhiều ảnh/video gửi 1 lần -> 1 khung lưới
    }

    /// Khoá album: cùng người gửi + cùng mã album (ảnh/video/gif chưa thu hồi, đã có file).
    static func khoaAlbum(_ t: Tin) -> String? {
        guard let a = t.phu?.album, !t.thuHoi, t.file != nil, ["anh", "video", "gif"].contains(t.kieu) else { return nil }
        return "\(t.uid ?? "")|\(t.laToi)|\(a.id)"
    }

    static func gomTheoNgay(_ ds: [Tin]) -> [MucHienThi] {
        // gom tin LIỀN KỀ cùng album thành 1 cụm (album 1 tin thì vẫn là tin thường)
        var cum: [[Tin]] = []
        for t in ds {
            if let k = khoaAlbum(t), let cuoi = cum.last?.last, khoaAlbum(cuoi) == k { cum[cum.count - 1].append(t) }
            else { cum.append([t]) }
        }
        var ketQua: [MucHienThi] = []
        var ngayTruoc = ""
        let cal = Calendar.current
        for (i, c) in cum.enumerated() {
            let t = c[0]
            let d = Date(timeIntervalSince1970: TimeInterval(t.ts) / 1000)
            let khoaNgay = cal.startOfDay(for: d).description
            var truocLienKe: Tin? = i > 0 ? cum[i - 1].last : nil
            if khoaNgay != ngayTruoc {
                ketQua.append(.ngay(DinhDang.ngayDai(t.ts)))
                ngayTruoc = khoaNgay
                truocLienKe = nil   // sang ngay moi thi khong gop nhom voi tin hom truoc
            }
            let dauNhom = !cungNhom(hienTai: t, truoc: truocLienKe)
            let sau = i + 1 < cum.count ? cum[i + 1].first : nil
            let cuoi = cuoiNhom(hienTai: c[c.count - 1], sau: sau)
            if c.count > 1 {
                ketQua.append(.album(c.sorted { ($0.phu?.album?.i ?? 0, $0.ts) < ($1.phu?.album?.i ?? 0, $1.ts) },
                                     dauNhom: dauNhom, cuoiNhom: cuoi))
            } else {
                ketQua.append(.tin(t, dauNhom: dauNhom, cuoiNhom: cuoi))
            }
        }
        return ketQua
    }
}

enum DinhDangChu {
    /// Khớp `chuCoTag()` trong web: cắt chuỗi theo vị trí UTF-16 (Zalo tính pos/len kiểu JS) để tô "@Tên".
    /// Trả về từng đoạn (text, co_phai_tag) theo đúng thứ tự xuất hiện trong chu.
    static func phanDoanTag(_ chu: String, tags: [TagMark]?) -> [(text: String, laTag: Bool)] {
        guard !chu.isEmpty else { return [] }
        guard let tags, !tags.isEmpty else { return [(chu, false)] }
        let utf16 = Array(chu.utf16)
        let hopLe = tags.filter { $0.pos >= 0 && $0.len > 0 && $0.pos + $0.len <= utf16.count }.sorted { $0.pos < $1.pos }
        guard !hopLe.isEmpty else { return [(chu, false)] }
        var ketQua: [(String, Bool)] = []
        var tu = 0
        for m in hopLe {
            if m.pos < tu { continue }   // trung voi tag truoc -> bo qua (giong web)
            if m.pos > tu { ketQua.append((String(decoding: utf16[tu..<m.pos], as: UTF16.self), false)) }
            if (m.pos + m.len) <= utf16.count {
                ketQua.append((String(decoding: utf16[m.pos..<(m.pos + m.len)], as: UTF16.self), true))
            }
            tu = m.pos + m.len
        }
        if tu < utf16.count { ketQua.append((String(decoding: utf16[tu...], as: UTF16.self), false)) }
        return ketQua
    }

    /// Khớp `tinhTag()` trong web/luu_tru: tìm lại từng "@Tên" đã chọn trong chữ cuối cùng -> [TagMark(uid, pos, len)].
    /// pos và len tính theo đơn vị mã UTF-16 (tương thích JavaScript/Node.js trên máy chủ và Zalo).
    static func tinhTag(chu: String, daChon: [TagChon]) -> [TagMark] {
        guard !chu.isEmpty else { return [] }
        let utf16 = Array(chu.utf16)
        var kq: [TagMark] = []

        // 1. Tìm các tag đã chọn từ danh sách gợi ý
        for item in daChon {
            let nhan = "@" + item.ten
            let nhanUtf16 = Array(nhan.utf16)
            guard !nhanUtf16.isEmpty, nhanUtf16.count <= utf16.count else { continue }

            var i = 0
            while i <= utf16.count - nhanUtf16.count {
                if Array(utf16[i..<(i + nhanUtf16.count)]) == nhanUtf16 {
                    let overlap = kq.contains { m in
                        i < (m.pos + m.len) && m.pos < (i + nhanUtf16.count)
                    }
                    if !overlap {
                        kq.append(TagMark(uid: item.uid, pos: i, len: nhanUtf16.count))
                        break
                    }
                }
                i += 1
            }
        }

        // 2. Dự phòng: nếu người dùng gõ tay @All / @all mà không chọn từ popup
        let allVariants = ["@All", "@all", "@ALL"]
        for v in allVariants {
            let vUtf16 = Array(v.utf16)
            var i = 0
            while i <= utf16.count - vUtf16.count {
                if Array(utf16[i..<(i + vUtf16.count)]) == vUtf16 {
                    let truocHopLe = (i == 0 || utf16[i - 1] == 0x20 || utf16[i - 1] == 0x0A)
                    let sauHopLe = (i + vUtf16.count == utf16.count || utf16[i + vUtf16.count] == 0x20 || utf16[i + vUtf16.count] == 0x0A)
                    let overlap = kq.contains { m in
                        i < (m.pos + m.len) && m.pos < (i + vUtf16.count)
                    }
                    if truocHopLe && sauHopLe && !overlap {
                        kq.append(TagMark(uid: "-1", pos: i, len: vUtf16.count))
                    }
                }
                i += 1
            }
        }

        return kq.sorted { $0.pos < $1.pos }
    }
}

struct TagChon: Codable, Equatable, Hashable {
    let uid: String
    let ten: String
}

extension String {
    /// Bỏ dấu tiếng Việt, chuyển chữ thường để tìm kiếm / lọc tên thành viên (khớp boDau() trên web).
    var boDau: String {
        self.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi"))
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
            .lowercased()
    }
}

enum PhanTrang {
    /// Khớp `ganTin()` trong web: thêm/thay 1 tin vào danh sách đang xem, giữ thứ tự theo ts tăng dần.
    static func ganTin(_ ds: [Tin], _ t: Tin) -> [Tin] {
        var ds = ds
        if let i = ds.firstIndex(where: { $0.msgId == t.msgId }) { ds[i] = t }
        else { ds.append(t); ds.sort { $0.ts < $1.ts } }
        return ds
    }

    /// Nối thêm 1 trang tin CŨ HƠN vào đầu danh sách (kéo lên tải thêm). Trả về (danh sách mới, đã hết hay chưa).
    static func noiTrangCu(hienTai: [Tin], trangCu: [Tin], nguongHetTin: Int = 60) -> (ds: [Tin], heTin: Bool) {
        (trangCu + hienTai, trangCu.count < nguongHetTin)
    }
}
