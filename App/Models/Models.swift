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

    // Cam xuc cua chinh minh (uidToi truyen vao vi server khong gui san co/khong)
    func camXucCuaToi(uidToi: String) -> [CamXucTin] { camXuc.filter { $0.uid == uidToi } }
    var duocThaCamXuc: Bool { cliMsgId != nil && !thuHoi }
    var duocThuHoi: Bool { laToi && !thuHoi && cliMsgId != nil }
    var duocChuyenTiep: Bool {
        !thuHoi && ((kieu == "chu" && !(chu ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || kieu == "sticker" || file != nil)
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
    var ngayTao: Date

    init(id: String = UUID().uuidString, ten: String, dsCuocId: [String] = [], ngayTao: Date = Date()) {
        self.id = id
        self.ten = ten
        self.dsCuocId = dsCuocId
        self.ngayTao = ngayTao
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
