// Các kiểu dữ liệu khớp với JSON của web_zalo.mjs / luu_tru.mjs (xem web/index.html để đối chiếu).
// Tên trường giữ đúng snake_case như server trả về qua CodingKeys tường minh (an toàn hơn convertFromSnakeCase
// vì có "phu" là khối JSON tự do với các khoá camelCase bên trong).

import Foundation

// ---------------------------------------------------------------- Người (avatar/tên trong nhóm)
struct Nguoi: Codable, Equatable {
    let uid: String?
    let ten: String?
    let anh: String?
    let capNhatLuc: Int64?

    enum CodingKeys: String, CodingKey {
        case uid, ten, anh
        case capNhatLuc = "cap_nhat_luc"
    }
}

// ---------------------------------------------------------------- Xem trước tin cuối (trong danh sách hội thoại)
struct TinCuoiPreview: Codable, Equatable, Hashable {
    let ten: String?
    let laToi: Bool?
    let xem: String?

    enum CodingKeys: String, CodingKey {
        case ten, xem
        case laToi = "la_toi"
    }
}

// ---------------------------------------------------------------- Hội thoại (người / nhóm / Sổ tay)
struct Cuoc: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let laNhom: Int          // 0 | 1 (SQLite thô, không phải Bool)
    let ten: String?
    let anh: String?
    let tinCuoiTs: Int64?
    let tinCuoi: TinCuoiPreview?
    let chuaDoc: Int
    let capNhatLuc: Int64?
    let ghim: Int?           // thứ tự ghim, null = không ghim
    let tatTb: Bool?         // chỉ xuất hiện (= true) khi nhóm đã tắt thông báo

    var laNhomBool: Bool { laNhom != 0 }
    var nguoiNhanChiaSe: NguoiNhanChiaSe { NguoiNhanChiaSe(id: id, ten: ten ?? id, laNhom: laNhomBool) }
    var daGhim: Bool { ghim != nil }
    var daTatThongBao: Bool { tatTb == true }

    enum CodingKeys: String, CodingKey {
        case id, ten, anh, ghim
        case laNhom = "la_nhom"
        case tinCuoiTs = "tin_cuoi_ts"
        case tinCuoi = "tin_cuoi"
        case chuaDoc = "chua_doc"
        case capNhatLuc = "cap_nhat_luc"
        case tatTb = "tat_tb"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        laNhom = try c.decodeIfPresent(Int.self, forKey: .laNhom) ?? 0
        ten = try c.decodeIfPresent(String.self, forKey: .ten)
        anh = try c.decodeIfPresent(String.self, forKey: .anh)
        tinCuoiTs = try c.decodeIfPresent(Int64.self, forKey: .tinCuoiTs)
        chuaDoc = try c.decodeIfPresent(Int.self, forKey: .chuaDoc) ?? 0
        capNhatLuc = try c.decodeIfPresent(Int64.self, forKey: .capNhatLuc)
        ghim = try c.decodeIfPresent(Int.self, forKey: .ghim)
        tatTb = try c.decodeIfPresent(Bool.self, forKey: .tatTb)
        // BUG/QUIRK thật của server: /api/tin trả "cuoc" qua layCuoc() KHÔNG JSON.parse cột tin_cuoi
        // (dsCuoc() dùng cho /api/cuoc thì có parse) -> tin_cuoi khi đó là CHUỖI JSON thô, không phải object.
        // Khoan dung cả 2 dạng ở đây, không sửa server.
        if let obj = try? c.decode(TinCuoiPreview.self, forKey: .tinCuoi) {
            tinCuoi = obj
        } else if let raw = try? c.decode(String.self, forKey: .tinCuoi), !raw.isEmpty,
                  let data = raw.data(using: .utf8), let obj = try? JSONDecoder().decode(TinCuoiPreview.self, from: data) {
            tinCuoi = obj
        } else {
            tinCuoi = nil
        }
    }

    init(id: String, laNhom: Int, ten: String?, anh: String?, tinCuoiTs: Int64?, tinCuoi: TinCuoiPreview?,
         chuaDoc: Int, capNhatLuc: Int64?, ghim: Int?, tatTb: Bool?) {
        self.id = id; self.laNhom = laNhom; self.ten = ten; self.anh = anh; self.tinCuoiTs = tinCuoiTs
        self.tinCuoi = tinCuoi; self.chuaDoc = chuaDoc; self.capNhatLuc = capNhatLuc; self.ghim = ghim; self.tatTb = tatTb
    }
}

// ---------------------------------------------------------------- Trích dẫn (trả lời 1 tin khác)
struct TrichDan: Codable, Equatable, Hashable {
    let ten: String?
    let chu: String?
    let msgId: String?

    enum CodingKeys: String, CodingKey {
        case ten, chu
        case msgId = "msg_id"
    }
}

// ---------------------------------------------------------------- Cảm xúc (ai thả gì)
struct CamXucTin: Codable, Equatable, Hashable, Identifiable {
    let uid: String
    let icon: String
    let ts: Int64?
    var id: String { uid + icon }
}

// ---------------------------------------------------------------- Vị trí "@Tên" được tag trong 1 tin
struct TagMark: Codable, Equatable, Hashable {
    let uid: String
    let pos: Int
    let len: Int
}

// ---------------------------------------------------------------- Lịch hẹn gắn với 1 tin (kieu == "lich")
struct LichHen: Codable, Equatable, Hashable {
    let id: String?
    let tieuDe: String?
    let emoji: String?
    let batDau: Int64?
    let lap: Int?              // 0 khong lap, 1 ngay, 2 tuan, 3 thang
    let rieng: Bool?
    let dienThoai: Bool?
    let cuocLich: String?
    let daXoa: Bool?
    let cuocNguon: String?      // cuoc chua tin goc (khi the lich hien o noi khac, vd So tay)
    let msgNguon: String?
    let taoLuc: Int64?
    let tenCuoc: String?
    let cuaToi: Bool?
}

// ---------------------------------------------------------------- Danh thiếp / Liên hệ (kieu == "danh-thiep")
struct DanhThiepInfo: Codable, Equatable, Hashable {
    let ten: String?
    let sdt: String?
    let uid: String?
    let avatar: String?
    let qrCode: String?
}

// ---------------------------------------------------------------- Tin nhắn đã ghim
struct TinGhim: Identifiable, Codable, Equatable, Hashable {
    var id: String { msgId }
    let msgId: String
    let cuocId: String?
    let tieuDe: String?
    let nguoiGhim: String?
    let ghimTs: Int64?
    let tin: Tin?

    init(msgId: String, cuocId: String? = nil, tieuDe: String? = nil, nguoiGhim: String? = nil, ghimTs: Int64? = nil, tin: Tin? = nil) {
        self.msgId = msgId
        self.cuocId = cuocId
        self.tieuDe = tieuDe
        self.nguoiGhim = nguoiGhim
        self.ghimTs = ghimTs
        self.tin = tin
    }
}

// ---------------------------------------------------------------- Khối "phu" tự do (khac nhau theo loai tin)
struct Phu: Codable, Equatable, Hashable {
    let khung: Int?             // sticker dong: so khung sprite ngang
    let ms: Int?                // sticker dong: thoi gian 1 khung (mili giay)
    let lich: LichHen?
    let tag: [TagMark]?
    let cuocNguon: String?
    let album: AlbumInfo?       // anh/video gui 1 lan (Zalo hien 1 khung luoi) - v4.3
    let danhThiep: DanhThiepInfo?
    let chuyenKhoan: ChuyenKhoanInfo?
    let binhChon: BinhChonInfo?

    init(khung: Int? = nil, ms: Int? = nil, lich: LichHen? = nil, tag: [TagMark]? = nil, cuocNguon: String? = nil, album: AlbumInfo? = nil, danhThiep: DanhThiepInfo? = nil, chuyenKhoan: ChuyenKhoanInfo? = nil, binhChon: BinhChonInfo? = nil) {
        self.khung = khung
        self.ms = ms
        self.lich = lich
        self.tag = tag
        self.cuocNguon = cuocNguon
        self.album = album
        self.danhThiep = danhThiep
        self.chuyenKhoan = chuyenKhoan
        self.binhChon = binhChon
    }
}

// ---------------------------------------------------------------- Thông tin chuyển khoản VietQR
struct ChuyenKhoanInfo: Codable, Equatable, Hashable {
    let nganHang: String
    let maNganHang: String
    let bin: String?
    let stk: String
    let tenNguoiNhan: String?
    let soTien: Int64?
    let noiDung: String?
    let qrUrl: String

    private static let dinhDangTien: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        return f
    }()

    var soTienDinhDang: String? {
        guard let tien = soTien, tien > 0 else { return nil }
        return (Self.dinhDangTien.string(from: NSNumber(value: tien)) ?? "\(tien)") + " đ"
    }

    var thongTinSaoChep: String {
        var dong: [String] = []
        dong.append("Ngân hàng: \(nganHang)")
        dong.append("Số tài khoản: \(stk)")
        if let ten = tenNguoiNhan, !ten.isEmpty { dong.append("Chủ tài khoản: \(ten)") }
        if let st = soTienDinhDang { dong.append("Số tiền: \(st)") }
        if let nd = noiDung, !nd.isEmpty { dong.append("Nội dung: \(nd)") }
        return dong.joined(separator: "\n")
    }
}

// ---------------------------------------------------------------- Bình chọn nhóm (Poll)
struct BinhChonLuaChon: Codable, Equatable, Hashable, Identifiable {
    var id: Int { optionId }
    let optionId: Int
    let content: String
    let votes: Int
    let voted: Bool?
    let voters: [String]?
    let percentage: Double?

    enum CodingKeys: String, CodingKey {
        case content, votes, voted, voters, percentage
        case optionId = "id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? c.decode(Int.self, forKey: .optionId) {
            optionId = intId
        } else if let strId = try? c.decode(String.self, forKey: .optionId), let intId = Int(strId) {
            optionId = intId
        } else {
            optionId = 0
        }
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        votes = try c.decodeIfPresent(Int.self, forKey: .votes) ?? 0
        voted = try c.decodeIfPresent(Bool.self, forKey: .voted)
        voters = try c.decodeIfPresent([String].self, forKey: .voters)
        percentage = try c.decodeIfPresent(Double.self, forKey: .percentage)
    }

    init(optionId: Int, content: String, votes: Int, voted: Bool? = nil, voters: [String]? = nil, percentage: Double? = nil) {
        self.optionId = optionId
        self.content = content
        self.votes = votes
        self.voted = voted
        self.voters = voters
        self.percentage = percentage
    }
}

struct BinhChonInfo: Codable, Equatable, Hashable {
    let pollId: String
    let cauHoi: String
    let options: [BinhChonLuaChon]
    let totalVotes: Int?
    let allowMultiChoices: Bool?
    let allowAddNewOption: Bool?
    let isAnonymous: Bool?
    let isClosed: Bool?
    let myVotes: [Int]?
    let creatorId: String?

    enum CodingKeys: String, CodingKey {
        case options, totalVotes, allowMultiChoices, allowAddNewOption, isAnonymous, isClosed, myVotes, creatorId
        case pollId = "pollId"
        case cauHoi = "cauHoi"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pollId = try c.decodeIfPresent(String.self, forKey: .pollId) ?? ""
        cauHoi = try c.decodeIfPresent(String.self, forKey: .cauHoi) ?? "Bình chọn"
        options = try c.decodeIfPresent([BinhChonLuaChon].self, forKey: .options) ?? []
        totalVotes = try c.decodeIfPresent(Int.self, forKey: .totalVotes)
        allowMultiChoices = try c.decodeIfPresent(Bool.self, forKey: .allowMultiChoices)
        allowAddNewOption = try c.decodeIfPresent(Bool.self, forKey: .allowAddNewOption)
        isAnonymous = try c.decodeIfPresent(Bool.self, forKey: .isAnonymous)
        isClosed = try c.decodeIfPresent(Bool.self, forKey: .isClosed)
        myVotes = try c.decodeIfPresent([Int].self, forKey: .myVotes)
        creatorId = try c.decodeIfPresent(String.self, forKey: .creatorId)
    }

    init(pollId: String, cauHoi: String, options: [BinhChonLuaChon], totalVotes: Int? = nil,
         allowMultiChoices: Bool? = nil, allowAddNewOption: Bool? = nil, isAnonymous: Bool? = nil,
         isClosed: Bool? = nil, myVotes: [Int]? = nil, creatorId: String? = nil) {
        self.pollId = pollId
        self.cauHoi = cauHoi
        self.options = options
        self.totalVotes = totalVotes
        self.allowMultiChoices = allowMultiChoices
        self.allowAddNewOption = allowAddNewOption
        self.isAnonymous = isAnonymous
        self.isClosed = isClosed
        self.myVotes = myVotes
        self.creatorId = creatorId
    }
}

/// Album: cùng `id` = cùng 1 lần gửi nhiều ảnh/video; `i` thứ tự trong album, `n` tổng số (máy chủ lấy từ group_layout_id).
struct AlbumInfo: Codable, Equatable, Hashable {
    let id: String
    let i: Int
    let n: Int
}

// ---------------------------------------------------------------- 1 tin nhắn
struct Tin: Codable, Equatable, Hashable, Identifiable {
    let msgId: String
    let cliMsgId: String?
    let cuocId: String?
    let uid: String?
    let tenNguoi: String?
    let laToi: Bool
    let ts: Int64
    let loai: String?
    let kieu: String             // chu | anh | gif | video | sticker | ghiam | file | lich
    let chu: String?
    let url: String?
    let file: String?
    let tenFile: String?
    let kichThuoc: Int64?
    let quote: TrichDan?
    let thuHoi: Bool
    let phu: Phu?
    let camXuc: [CamXucTin]
    // chi co trong ket qua /api/tim (JOIN voi bang cuoc)
    let tenCuoc: String?
    let laNhomCuoc: Int?

    var id: String { msgId }

    enum CodingKeys: String, CodingKey {
        case kieu, chu, url, file, quote, phu
        case msgId = "msg_id"
        case cliMsgId = "cli_msg_id"
        case cuocId = "cuoc_id"
        case uid
        case tenNguoi = "ten_nguoi"
        case laToi = "la_toi"
        case ts, loai
        case tenFile = "ten_file"
        case kichThuoc = "kich_thuoc"
        case thuHoi = "thu_hoi"
        case camXuc = "cam_xuc"
        case tenCuoc = "ten_cuoc"
        case laNhomCuoc = "la_nhom"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        msgId = try c.decode(String.self, forKey: .msgId)
        cliMsgId = try c.decodeIfPresent(String.self, forKey: .cliMsgId)
        cuocId = try c.decodeIfPresent(String.self, forKey: .cuocId)
        uid = try c.decodeIfPresent(String.self, forKey: .uid)
        tenNguoi = try c.decodeIfPresent(String.self, forKey: .tenNguoi)
        laToi = try c.decodeIfPresent(Bool.self, forKey: .laToi) ?? false
        ts = try c.decode(Int64.self, forKey: .ts)
        loai = try c.decodeIfPresent(String.self, forKey: .loai)
        kieu = try c.decodeIfPresent(String.self, forKey: .kieu) ?? "chu"
        chu = try c.decodeIfPresent(String.self, forKey: .chu)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        file = try c.decodeIfPresent(String.self, forKey: .file)
        tenFile = try c.decodeIfPresent(String.self, forKey: .tenFile)
        kichThuoc = try c.decodeIfPresent(Int64.self, forKey: .kichThuoc)
        quote = try c.decodeIfPresent(TrichDan.self, forKey: .quote)
        thuHoi = try c.decodeIfPresent(Bool.self, forKey: .thuHoi) ?? false
        phu = try c.decodeIfPresent(Phu.self, forKey: .phu)
        camXuc = try c.decodeIfPresent([CamXucTin].self, forKey: .camXuc) ?? []
        tenCuoc = try c.decodeIfPresent(String.self, forKey: .tenCuoc)
        laNhomCuoc = try c.decodeIfPresent(Int.self, forKey: .laNhomCuoc)
    }

    init(msgId: String, cliMsgId: String?, cuocId: String?, uid: String?, tenNguoi: String?, laToi: Bool, ts: Int64,
         loai: String?, kieu: String, chu: String?, url: String?, file: String?, tenFile: String?, kichThuoc: Int64?,
         quote: TrichDan?, thuHoi: Bool, phu: Phu?, camXuc: [CamXucTin], tenCuoc: String? = nil, laNhomCuoc: Int? = nil) {
        self.msgId = msgId; self.cliMsgId = cliMsgId; self.cuocId = cuocId; self.uid = uid; self.tenNguoi = tenNguoi
        self.laToi = laToi; self.ts = ts; self.loai = loai; self.kieu = kieu; self.chu = chu; self.url = url
        self.file = file; self.tenFile = tenFile; self.kichThuoc = kichThuoc; self.quote = quote; self.thuHoi = thuHoi
        self.phu = phu; self.camXuc = camXuc; self.tenCuoc = tenCuoc; self.laNhomCuoc = laNhomCuoc
    }

    /// v5.4: gắn tên/loại hội thoại cho tin lấy từ bộ nhớ máy (kết quả tìm kiếm cần tenCuoc + cuocId).
    func ganCuoc(_ c: Cuoc?, cuocId: String) -> Tin {
        Tin(msgId: msgId, cliMsgId: cliMsgId, cuocId: self.cuocId ?? cuocId, uid: uid, tenNguoi: tenNguoi, laToi: laToi,
            ts: ts, loai: loai, kieu: kieu, chu: chu, url: url, file: file, tenFile: tenFile, kichThuoc: kichThuoc,
            quote: quote, thuHoi: thuHoi, phu: phu, camXuc: camXuc,
            tenCuoc: tenCuoc ?? c?.ten, laNhomCuoc: laNhomCuoc ?? c?.laNhom)
    }

    // Cam xuc cua chinh minh (uidToi truyen vao vi server khong gui san co/khong)
    func camXucCuaToi(uidToi: String) -> [CamXucTin] { camXuc.filter { $0.uid == uidToi } }
    var duocThaCamXuc: Bool { cliMsgId != nil && !thuHoi }
    var duocThuHoi: Bool { laToi && !thuHoi && cliMsgId != nil }
    var duocChuyenTiep: Bool {
        !thuHoi && ((kieu == "chu" && !(chu ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || kieu == "sticker" || file != nil)
    }

    /// Thông tin chuyển khoản: máy chủ gửi sẵn, hoặc tự nhận diện từ chữ (có bộ đệm - body gọi lại liên tục khi cuộn).
    var thongTinChuyenKhoan: ChuyenKhoanInfo? {
        if let ck = phu?.chuyenKhoan { return ck }
        guard !thuHoi, kieu == "chu", let chu, chu.count >= 8 else { return nil }
        return BankDetector.parseCoDem(text: chu)
    }

    var thongTinBinhChon: BinhChonInfo? { phu?.binhChon }

    /// v6.2: các loại tin Zalo máy chủ chưa giải mã (lưu dạng "[Loại tin chưa hỗ trợ: ...]" / "[chat.ecard]").
    var loaiDacBiet: LoaiTinDacBiet? {
        switch loai {
        case "chat.ecard":
            // thẻ nhắc hẹn Zalo: máy chủ lưu ảnh nền thẻ thành "file", tiêu đề nằm ở ten_file ("⏰ Đặt hàng...")
            let tieuDe = (tenFile ?? "").trimmingCharacters(in: .whitespaces)
            if let dau = tieuDe.first, dau.unicodeScalars.first?.properties.isEmojiPresentation == true {
                return .nhacHen(emoji: String(dau), tieuDe: String(tieuDe.dropFirst()).trimmingCharacters(in: .whitespaces))
            }
            return .nhacHen(emoji: "⏰", tieuDe: tieuDe)
        case "group.poll" where phu?.binhChon == nil: return .binhChonCu
        // thẻ ngân hàng: máy chủ giải mã gửi phu.chuyenKhoan / chu "VPBank - <stk>" -> hiện thẻ chuyển khoản
        case "chat.webcontent" where thongTinChuyenKhoan == nil: return .theZalo
        case "chat.delete": return .daXoa
        default:
            guard let chu, chu.hasPrefix("[Loại tin chưa hỗ trợ") else { return nil }
            return .chuaHoTro
        }
    }

    /// Bản sao với phần phụ mới (cập nhật bình chọn realtime).
    func voiPhu(_ phuMoi: Phu?) -> Tin {
        Tin(msgId: msgId, cliMsgId: cliMsgId, cuocId: cuocId, uid: uid, tenNguoi: tenNguoi, laToi: laToi, ts: ts,
            loai: loai, kieu: kieu, chu: chu, url: url, file: file, tenFile: tenFile, kichThuoc: kichThuoc,
            quote: quote, thuHoi: thuHoi, phu: phuMoi, camXuc: camXuc, tenCuoc: tenCuoc, laNhomCuoc: laNhomCuoc)
    }
}

// ---------------------------------------------------------------- Phản hồi /api/tin
struct PhanHoiTin: Codable {
    let cuoc: Cuoc?
    let tin: [Tin]
    let toi: String?
    let nguoi: [String: Nguoi?]
    let dsGhim: [TinGhim]?
}

// ---------------------------------------------------------------- Phản hồi /api/kho
struct DemKho: Codable {
    let anh: Int?
    let file: Int?
    let pdf: Int?
    let word: Int?
    let ppt: Int?
    let excel: Int?
    let khac: Int?
    let link: Int?
}
struct PhanHoiKho: Codable {
    let dem: DemKho?
    let ds: [Tin]
}

// ---------------------------------------------------------------- Thành viên nhóm (goi y tag)
struct ThanhVien: Codable, Equatable, Identifiable {
    let uid: String
    let ten: String
    let anh: String?
    var id: String { uid }
}

// ---------------------------------------------------------------- Nhóm tùy chọn (người dùng tự tạo: Đặt hàng, Nhóm, v.v.)
struct NhomTuyChon: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var ten: String
    var dsCuocId: [String]
    var ngayTao: Date?

    enum CodingKeys: String, CodingKey {
        case id, ten, dsCuocId, ngayTao
    }

    init(id: String = UUID().uuidString, ten: String, dsCuocId: [String] = [], ngayTao: Date? = Date()) {
        self.id = id
        self.ten = ten
        self.dsCuocId = dsCuocId
        self.ngayTao = ngayTao
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        ten = try c.decodeIfPresent(String.self, forKey: .ten) ?? "Nhóm"
        dsCuocId = try c.decodeIfPresent([String].self, forKey: .dsCuocId) ?? []
        if let ts = try? c.decodeIfPresent(Double.self, forKey: .ngayTao) {
            ngayTao = Date(timeIntervalSince1970: ts > 1_000_000_000_000 ? ts / 1000 : ts)
        } else {
            ngayTao = try? c.decodeIfPresent(Date.self, forKey: .ngayTao)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(ten, forKey: .ten)
        try c.encode(dsCuocId, forKey: .dsCuocId)
        if let ngayTao {
            try c.encode(Int64(ngayTao.timeIntervalSince1970 * 1000), forKey: .ngayTao)
        }
    }
}

// ---------------------------------------------------------------- Trạng thái đăng nhập Zalo Web trên máy chủ
struct ZaloServerStatus: Codable, Equatable {
    let daDangNhap: Bool
    let trangThai: String
    let uid: String?
    let ten: String?
    let qr: String?
    let loi: String?

    enum CodingKeys: String, CodingKey {
        case daDangNhap
        case trangThai
        case uid
        case ten
        case qr
        case loi
    }
}

// ---------------------------------------------------------------- Bộ nhận diện thông tin chuyển khoản ngân hàng (VietQR)
enum BankDetector {
    struct NganHang {
        let ma: String
        let bin: String
        let ten: String
        let tuKhoa: [String]
    }

    static let danhSach: [NganHang] = [
        NganHang(ma: "vietinbank", bin: "970415", ten: "VietinBank", tuKhoa: ["vietinbank", "vietin", "ctg", "icb"]),
        NganHang(ma: "vietcombank", bin: "970436", ten: "Vietcombank", tuKhoa: ["vietcombank", "vcb"]),
        NganHang(ma: "bidv", bin: "970418", ten: "BIDV", tuKhoa: ["bidv"]),
        NganHang(ma: "mbbank", bin: "970422", ten: "MBBank", tuKhoa: ["mbbank", "mb bank", "mb"]),
        NganHang(ma: "techcombank", bin: "970407", ten: "Techcombank", tuKhoa: ["techcombank", "techcom", "tcb"]),
        NganHang(ma: "acb", bin: "970416", ten: "ACB", tuKhoa: ["acb", "á châu"]),
        NganHang(ma: "vpbank", bin: "970432", ten: "VPBank", tuKhoa: ["vpbank", "vpb", "việt nam thịnh vượng"]),
        NganHang(ma: "tpbank", bin: "970423", ten: "TPBank", tuKhoa: ["tpbank", "tpb", "tiên phong"]),
        NganHang(ma: "sacombank", bin: "970403", ten: "Sacombank", tuKhoa: ["sacombank", "stb", "sài gòn thương tín"]),
        NganHang(ma: "hdbank", bin: "970437", ten: "HDBank", tuKhoa: ["hdbank", "hdb"]),
        NganHang(ma: "vib", bin: "970441", ten: "VIB", tuKhoa: ["vib"]),
        NganHang(ma: "shb", bin: "970443", ten: "SHB", tuKhoa: ["shb"]),
        NganHang(ma: "msb", bin: "970426", ten: "MSB", tuKhoa: ["msb", "hàng hải"]),
        NganHang(ma: "ocb", bin: "970448", ten: "OCB", tuKhoa: ["ocb", "phương đông"]),
        NganHang(ma: "lpbank", bin: "970449", ten: "LPBank", tuKhoa: ["lpbank", "lpb", "lienvietpostbank", "liên việt"]),
        NganHang(ma: "seabank", bin: "970440", ten: "SeABank", tuKhoa: ["seabank"]),
        NganHang(ma: "agribank", bin: "970405", ten: "Agribank", tuKhoa: ["agribank", "vba", "nông nghiệp"]),
        NganHang(ma: "namabank", bin: "970428", ten: "Nam A Bank", tuKhoa: ["nam a bank", "namabank", "nab"]),
        NganHang(ma: "bacabank", bin: "970409", ten: "Bac A Bank", tuKhoa: ["bac a bank", "bacabank", "bắc á"]),
        NganHang(ma: "bvbank", bin: "970454", ten: "BVBank", tuKhoa: ["bvbank", "bản việt"]),
        NganHang(ma: "pvcombank", bin: "970412", ten: "PVcomBank", tuKhoa: ["pvcombank", "pvb"]),
        NganHang(ma: "cake", bin: "546034", ten: "CAKE by VPBank", tuKhoa: ["cake"]),
        NganHang(ma: "timo", bin: "963388", ten: "Timo", tuKhoa: ["timo"]),
        NganHang(ma: "baovietbank", bin: "970438", ten: "BaoViet Bank", tuKhoa: ["baoviet", "bảo việt"]),
        NganHang(ma: "kienlongbank", bin: "970452", ten: "KienlongBank", tuKhoa: ["kienlong", "klb"]),
        NganHang(ma: "saigonbank", bin: "970400", ten: "Saigonbank", tuKhoa: ["saigonbank", "sgb"]),
        NganHang(ma: "pgbank", bin: "970430", ten: "PGBank", tuKhoa: ["pgbank", "pgb"]),
        NganHang(ma: "shinhanbank", bin: "970424", ten: "Shinhan Bank", tuKhoa: ["shinhan"]),
        NganHang(ma: "wooribank", bin: "970457", ten: "Woori Bank", tuKhoa: ["woori"])
    ]

    // Biên dịch regex 1 lần (trước đây mỗi tin x mỗi lần vẽ đều tạo lại ~30 regex -> cuộn chat giật).
    private static func re(_ mau: String, _ tuyChon: NSRegularExpression.Options = .caseInsensitive) -> NSRegularExpression {
        try! NSRegularExpression(pattern: mau, options: tuyChon)
    }
    private static let reDayso = re("\\d{6,}", [])
    private static let reStk = re("(?:stk|số tài khoản|so tai khoan|\\btk)\\s*[:.]?\\s*(\\d{6,19})")
    private static let reChuSo = re("\\b\\d{8,19}\\b", [])
    private static let reTien = re("(\\d+(?:[.,]\\d{3})*)\\s*(k|tr|triệu|trieu|đ|vnd|dong|đồng)\\b")
    private static let reTen = re("(?:chủ tk|tên|ctk|người nhận|chủ tài khoản)\\s*[:.]?\\s*([A-ZÀ-Ỹa-zà-ỹ\\s]{3,40})")
    private static let reTenSauStk = re("^\\p{Lu}\\p{Ll}*(?: \\p{Lu}\\p{Ll}*){1,5}$", [])
    private static let reNoiDung = re("(?:nội dung|\\bnd|ndck|memo)\\s*[:.]?\\s*([^\\n\\r]{3,60})")
    /// Mỗi ngân hàng: từ khoá ngắn (<= 3 ký tự) phải đứng riêng 1 từ, từ khoá dài chỉ cần chứa.
    private static let khopNganHang: [(NganHang, NSRegularExpression?, [String])] = danhSach.map { b in
        let ngan = b.tuKhoa.filter { $0.count <= 3 }.map(NSRegularExpression.escapedPattern(for:))
        return (b, ngan.isEmpty ? nil : re("\\b(?:" + ngan.joined(separator: "|") + ")\\b"), b.tuKhoa.filter { $0.count > 3 })
    }

    private static let boDem = NSCache<NSString, HopKetQua>()
    private final class HopKetQua { let ck: ChuyenKhoanInfo?; init(_ ck: ChuyenKhoanInfo?) { self.ck = ck } }

    static func parseCoDem(text: String) -> ChuyenKhoanInfo? {
        if let hop = boDem.object(forKey: text as NSString) { return hop.ck }
        let ck = parse(text: text)
        boDem.setObject(HopKetQua(ck), forKey: text as NSString)
        return ck
    }

    private static func nhom(_ r: NSRegularExpression, _ text: String, _ i: Int = 1) -> String? {
        guard let m = r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let rg = Range(m.range(at: i), in: text) else { return nil }
        return String(text[rg])
    }

    static func parse(text: String) -> ChuyenKhoanInfo? {
        // lọc nhanh: không có dãy >= 6 chữ số thì chắc chắn không phải tin chuyển khoản
        guard reDayso.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil else { return nil }
        let lower = text.lowercased()
        let toanBo = NSRange(lower.startIndex..., in: lower)
        var khopTuDai = false
        // "VP bank", "Techcom bank"... viết tách: so thêm bản bỏ dấu cách với từ khoá đuôi "bank"
        let gon = lower.replacingOccurrences(of: " ", with: "")
        guard let bank = khopNganHang.first(where: { _, reNgan, dai in
            if dai.contains(where: { lower.contains($0) || ($0.hasSuffix("bank") && gon.contains($0)) }) { khopTuDai = true; return true }
            return reNgan?.firstMatch(in: lower, range: toanBo) != nil
        })?.0 else { return nil }

        // STK: ưu tiên có chữ "stk/tk/số tài khoản"; không có thì chỉ nhận dãy số trần khi tên ngân hàng rõ ràng
        // (từ khoá ngắn như "mb", "acb" + 1 số điện thoại bất kỳ dễ nhận nhầm)
        guard let finalStk = nhom(reStk, text) ?? (khopTuDai ? nhom(reChuSo, text, 0) : nil) else { return nil }

        var soTien: Int64? = nil
        if let m = reTien.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let rVal = Range(m.range(at: 1), in: text), let rDv = Range(m.range(at: 2), in: text),
           var val = Int64(text[rVal].replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")) {
            let dv = text[rDv].lowercased()
            if dv == "k" { val *= 1000 } else if ["tr", "triệu", "trieu"].contains(dv) { val *= 1_000_000 }
            soTien = val
        }

        var tenNguoiNhan = nhom(reTen, text)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if tenNguoiNhan == nil {
            let parts = text.components(separatedBy: "STK")
            if parts.count > 1, parts[0].trimmingCharacters(in: .whitespacesAndNewlines).count > 3 {
                let p0 = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: " ,.-:\n\r\t"))
                let lowerP0 = p0.lowercased()
                let hoVietNam = ["công ty", "cty", "nguyễn", "trần", "lê", "phạm", "hoàng", "huỳnh", "vũ", "võ", "đặng", "bùi", "đỗ", "hồ", "ngô", "dương", "lý"]
                if hoVietNam.contains(where: { lowerP0.contains($0) }) {
                    tenNguoiNhan = p0
                }
            }
        }

        // "VP bank 0934486685 Lê Văn Đức": họ tên viết liền sau số tài khoản
        if tenNguoiNhan == nil, let r = text.range(of: finalStk) {
            let sau = text[r.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " ,.-:\n\r\t"))
            if nhom(reTenSauStk, sau, 0) != nil { tenNguoiNhan = sau }
        }

        let noiDung = nhom(reNoiDung, text)?.trimmingCharacters(in: .whitespacesAndNewlines)

        var queryItems: [URLQueryItem] = []
        if let st = soTien { queryItems.append(URLQueryItem(name: "amount", value: "\(st)")) }
        if let t = tenNguoiNhan, !t.isEmpty { queryItems.append(URLQueryItem(name: "accountName", value: t)) }
        if let nd = noiDung, !nd.isEmpty { queryItems.append(URLQueryItem(name: "addInfo", value: nd)) }

        var comp = URLComponents(string: "https://img.vietqr.io/image/\(bank.ma)-\(finalStk)-compact2.png")
        if !queryItems.isEmpty { comp?.queryItems = queryItems }
        let qrUrl = comp?.url?.absoluteString ?? "https://img.vietqr.io/image/\(bank.ma)-\(finalStk)-compact2.png"

        return ChuyenKhoanInfo(
            nganHang: bank.ten,
            maNganHang: bank.ma,
            bin: bank.bin,
            stk: finalStk,
            tenNguoiNhan: tenNguoiNhan,
            soTien: soTien,
            noiDung: noiDung,
            qrUrl: qrUrl
        )
    }
}

// ---------------------------------------------------------------- v6.2: tin Zalo máy chủ chưa giải mã
enum LoaiTinDacBiet: Equatable {
    case nhacHen(emoji: String, tieuDe: String)
    case binhChonCu
    case theZalo
    case daXoa
    case chuaHoTro

    var xemTruoc: String {
        switch self {
        case .nhacHen(let e, let td): return "\(e) Nhắc hẹn: \(td)"
        case .binhChonCu: return "📊 Bình chọn"
        case .theZalo: return "💳 Thẻ Zalo"
        case .daXoa: return "Tin nhắn đã bị xoá"
        case .chuaHoTro: return "Tin nhắn Zalo"
        }
    }

    /// Đổi chữ xem trước thô của máy chủ ("[Loại tin chưa hỗ trợ: group.poll]", "[chat.ecard]") thành chữ dễ đọc.
    static func lamDepXemTruoc(_ s: String) -> String {
        if s.contains("[chat.ecard]") { return s.replacingOccurrences(of: "[chat.ecard]", with: "⏰ Nhắc hẹn") }
        guard let r = s.range(of: "[Loại tin chưa hỗ trợ: ") , let dong = s[r.upperBound...].firstIndex(of: "]") else { return s }
        let loai = String(s[r.upperBound..<dong])
        let dep: LoaiTinDacBiet
        switch loai {
        case "group.poll": dep = .binhChonCu
        case "chat.webcontent": dep = .theZalo
        case "chat.delete": dep = .daXoa
        default: dep = .chuaHoTro
        }
        return s.replacingCharacters(in: r.lowerBound...dong, with: dep.xemTruoc)
    }
}
