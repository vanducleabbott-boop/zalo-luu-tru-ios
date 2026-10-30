// Gọi các route của web_zalo.mjs (xem file đó + web/index.html để đối chiếu tham số/định dạng).
// Phiên đăng nhập = 1 cookie "zw=..." lưu trong HTTPCookieStorage.shared (persist qua lần mở app).

import Foundation

enum LoiZaloAPI: Error, LocalizedError {
    case chuaDangNhap
    case maHttp(Int, String)
    case diaChiKhongHopLe
    case canDangNhapCloudflare

    var errorDescription: String? {
        switch self {
        case .chuaDangNhap: return "Hết phiên đăng nhập"
        case .maHttp(let ma, let loi): return loi.isEmpty ? "Lỗi máy chủ (\(ma))" : loi
        case .diaChiKhongHopLe: return "Địa chỉ máy chủ không hợp lệ"
        case .canDangNhapCloudflare: return "Cần đăng nhập Cloudflare, đăng nhập xong thử lại"
        }
    }
}

/// Không tự theo 303 của /dang-nhap: cần đọc thẳng mã trạng thái + Set-Cookie của chính response đó.
private final class KhongTheoChuyenHuong: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                     newRequest request: URLRequest) async -> URLRequest? { nil }
}

final class ZaloAPI {
    private let session: URLSession
    private let khongChuyenHuong = KhongTheoChuyenHuong()
    var baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
        let cau = URLSessionConfiguration.default
        cau.httpCookieStorage = HTTPCookieStorage.shared
        cau.httpShouldSetCookies = true
        session = URLSession(configuration: cau)
    }

    /// v7.10: tải ảnh lên đi kết nối RIÊNG. 30/10: 1 lần tải bị đứt làm kết nối chung (HTTP/2 tới Cloudflare) nghẽn chiều
    /// gửi lên -> mọi lần tải sau xếp hàng chờ mãi, không tới được tunnel/bot, trong khi SSE vẫn chạy.
    private var phienTaiLen = ZaloAPI.taoPhienTaiLen()
    private static func taoPhienTaiLen() -> URLSession {
        let cau = URLSessionConfiguration.ephemeral
        cau.timeoutIntervalForRequest = 30      // 30s không nhích byte nào -> huỷ, thử lại trên kết nối mới
        cau.timeoutIntervalForResource = 300
        cau.httpShouldSetCookies = false        // cookie gắn tay (zw + CF_Authorization) trong goi()
        return URLSession(configuration: cau)
    }
    /// Bỏ kết nối tải lên cũ (có thể đang nghẽn), lần sau mở kết nối mới.
    func lamMoiKetNoiTaiLen() {
        phienTaiLen.finishTasksAndInvalidate()   // để lượt tải đang chạy (chat khác) xong nốt
        phienTaiLen = Self.taoPhienTaiLen()
    }

    // ---------------------------------------------------------------- tiện ích chung
    // Ghép chuỗi (không dùng appendingPathComponent vì "/api/cuoc" có nhiều đoạn, dễ bị chẻ sai).
    private func url(_ duongDan: String, query: [String: String?] = [:]) throws -> URL {
        var goc = baseURL.absoluteString
        while goc.hasSuffix("/") { goc.removeLast() }
        guard var c = URLComponents(string: goc + duongDan) else { throw LoiZaloAPI.diaChiKhongHopLe }
        let items = query.compactMapValues { $0 }.map { URLQueryItem(name: $0.key, value: $0.value) }
        if !items.isEmpty { c.queryItems = items }
        guard let u = c.url else { throw LoiZaloAPI.diaChiKhongHopLe }
        return u
    }

    @discardableResult
    private func goi(_ duongDan: String, method: String = "GET", query: [String: String?] = [:],
                      jsonBody: Encodable? = nil, rawBody: Data? = nil, headers: [String: String] = [:],
                      phien: URLSession? = nil) async throws -> Data {
        var req = URLRequest(url: try url(duongDan, query: query))
        req.httpMethod = method
        if let token = giaTriCookiePhien() {
            req.setValue("zw=\(token)", forHTTPHeaderField: "Cookie")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        CloudflareAccess.apply(to: &req)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let jsonBody {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(AnyEncodableBox(jsonBody))
        } else if let rawBody {
            req.httpBody = rawBody
        }
        let (data, resp) = try await (phien ?? session).data(for: req)
        if CloudflareAccess.isAccessResponse(resp, data: data) {
            CloudflareAccess.clear()
            Task { @MainActor in CloudflareAccess.shared.requestLogin(baseURL: self.baseURL) }
            throw LoiZaloAPI.canDangNhapCloudflare
        }
        guard let http = resp as? HTTPURLResponse else { return data }
        if http.statusCode == 401 { throw LoiZaloAPI.chuaDangNhap }
        if !(200...299).contains(http.statusCode) {
            let loi = (try? JSONDecoder().decode([String: String].self, from: data))?["loi"] ?? ""
            throw LoiZaloAPI.maHttp(http.statusCode, loi)
        }
        return data
    }

    private func goiJSON<T: Decodable>(_ duongDan: String, method: String = "GET", query: [String: String?] = [:],
                                        jsonBody: Encodable? = nil, rawBody: Data? = nil, headers: [String: String] = [:]) async throws -> T {
        let data = try await goi(duongDan, method: method, query: query, jsonBody: jsonBody, rawBody: rawBody, headers: headers)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // ---------------------------------------------------------------- đăng nhập (POST /dang-nhap, không phải JSON)
    /// true = đúng mật khẩu (cookie đã lưu vào HTTPCookieStorage.shared + UserDefaults); false = sai mật khẩu.
    func dangNhap(matKhau: String) async throws -> Bool {
        var req = URLRequest(url: try url("/dang-nhap"))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        CloudflareAccess.apply(to: &req)
        let form = "mk=" + (matKhau.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        req.httpBody = form.data(using: .utf8)
        let (_, resp) = try await session.data(for: req, delegate: khongChuyenHuong)
        let isAccess: Bool = {
            if CloudflareAccess.isAccessURL(resp.url) { return true }
            if let http = resp as? HTTPURLResponse, let loc = http.value(forHTTPHeaderField: "Location")?.lowercased(), loc.contains("cloudflareaccess.com") {
                return true
            }
            return false
        }()
        if isAccess {
            CloudflareAccess.clear()
            Task { @MainActor in CloudflareAccess.shared.requestLogin(baseURL: self.baseURL) }
            throw LoiZaloAPI.canDangNhapCloudflare
        }
        guard let http = resp as? HTTPURLResponse else { return false }
        if http.statusCode == 303 || (200...299).contains(http.statusCode) {
            // Trích xuất cookie zw từ header Set-Cookie
            for (k, v) in http.allHeaderFields {
                if String(describing: k).caseInsensitiveCompare("Set-Cookie") == .orderedSame {
                    let headerStr = String(describing: v)
                    if let range = headerStr.range(of: "zw=([^;]+)", options: .regularExpression) {
                        let match = String(headerStr[range])
                        let token = match.replacingOccurrences(of: "zw=", with: "")
                        UserDefaults.standard.set(token, forKey: "zl_session_zw")
                        print("[ZaloAPI] Da luu token zw vao UserDefaults: \(token.prefix(8))...")
                    }
                }
            }
            if let token = UserDefaults.standard.string(forKey: "zl_session_zw"), let u = resp.url, let host = u.host {
                let props: [HTTPCookiePropertyKey: Any] = [
                    .name: "zw",
                    .value: token,
                    .domain: host,
                    .path: "/",
                ]
                if let cookie = HTTPCookie(properties: props) {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
            }
            return true
        }
        return false
    }

    func dangXuat() {
        UserDefaults.standard.removeObject(forKey: "zl_session_zw")
        for c in HTTPCookieStorage.shared.cookies(for: baseURL) ?? [] { HTTPCookieStorage.shared.deleteCookie(c) }
        if let all = HTTPCookieStorage.shared.cookies {
            for c in all where c.name == "zw" {
                HTTPCookieStorage.shared.deleteCookie(c)
            }
        }
    }

    func daCoCookiePhien() -> Bool {
        giaTriCookiePhien() != nil
    }

    /// v7.4: ảnh đại diện gốc (nét nhất) - máy chủ gọi Zalo getFullAvatar; nil = không có / máy chủ chưa hỗ trợ.
    func anhDaiDienGoc(uid: String) async throws -> String? {
        struct KQ: Decodable { let url: String? }
        let kq: KQ = try await goiJSON("/api/anh-dai-dien", query: ["uid": uid])
        return kq.url
    }

    // ---------------------------------------------------------------- danh sách hội thoại + tìm kiếm
    func dsCuoc(tim: String = "") async throws -> [Cuoc] {
        try await goiJSON("/api/cuoc", query: ["tim": tim.isEmpty ? nil : tim])
    }

    func timKiemChung(q: String) async throws -> [Tin] {
        try await goiJSON("/api/tim", query: ["q": q])
    }

    func timTrongCuoc(cuoc: String, q: String, dem: Int = 200) async throws -> [Tin] {
        try await goiJSON("/api/tim", query: ["cuoc": cuoc, "q": q, "dem": String(dem)])
    }

    // ---------------------------------------------------------------- tin nhắn 1 cuộc
    func dsTin(cuoc: String, truoc: Int64? = nil, quanh: Int64? = nil) async throws -> PhanHoiTin {
        try await goiJSON("/api/tin", query: ["cuoc": cuoc, "truoc": truoc.map(String.init), "quanh": quanh.map(String.init)])
    }

    func danhDauDaDoc(cuoc: String) async throws {
        try await goi("/api/doc", method: "POST", query: ["cuoc": cuoc])
    }

    func layNguoi(uids: [String]) async throws -> [String: Nguoi?] {
        guard !uids.isEmpty else { return [:] }
        return try await goiJSON("/api/nguoi", query: ["uid": uids.joined(separator: ",")])
    }

    func layThanhVien(cuoc: String) async throws -> [ThanhVien] {
        try await goiJSON("/api/thanh-vien", query: ["cuoc": cuoc])
    }

    // ---------------------------------------------------------------- kho (ảnh/video, file, link)
    func layKho(cuoc: String, loai: String, nhom: String = "", truoc: Int64? = nil, demTong: Bool = false) async throws -> PhanHoiKho {
        try await goiJSON("/api/kho", query: ["cuoc": cuoc, "loai": loai, "nhom": nhom.isEmpty ? nil : nhom,
                                               "truoc": truoc.map(String.init), "dem": demTong ? "1" : nil])
    }

    // ---------------------------------------------------------------- gửi
    struct KetQuaGui: Decodable { let ok: Bool? }

    func guiChu(cuoc: String, chu: String, tag: [TagMark] = [], trichMsgId: String? = nil) async throws {
        struct Than: Encodable { let chu: String; let tag: [TagMark] }
        _ = try await goi("/api/gui", method: "POST", query: ["cuoc": cuoc, "trich": trichMsgId],
                           jsonBody: Than(chu: chu, tag: tag))
    }

    func guiFile(cuoc: String, duLieu: Data, tenFile: String, trichMsgId: String? = nil) async throws {
        let tenMaHoa = tenFile.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tenFile
        _ = try await goi("/api/gui", method: "POST", query: ["cuoc": cuoc, "trich": trichMsgId],
                           rawBody: duLieu, headers: ["X-Ten-File": tenMaHoa], phien: phienTaiLen)
    }

    // ---------------------------------------------------------------- album (v4.3, 20/10/2026)
    /// Tải 1 tệp lên máy chủ chờ gửi album, trả mã tạm (giữ 15 phút).
    func taiLenTam(duLieu: Data, tenFile: String) async throws -> String {
        struct KQ: Decodable { let ma: String }
        let tenMaHoa = tenFile.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tenFile
        let data = try await goi("/api/tai-len", method: "POST", rawBody: duLieu,
                                 headers: ["X-Ten-File": tenMaHoa, "Content-Type": "application/octet-stream"], phien: phienTaiLen)
        return try JSONDecoder().decode(KQ.self, from: data).ma
    }

    /// Gửi các tệp đã tải lên thành 1 album (Zalo hiện 1 khung lưới như Zalo gốc).
    func guiAlbum(cuoc: String, ma: [String]) async throws {
        struct Than: Encodable { let ma: [String] }
        _ = try await goi("/api/gui-album", method: "POST", query: ["cuoc": cuoc], jsonBody: Than(ma: ma))
    }

    // ---------------------------------------------------------------- sticker (v4.1, 19/10/2026)
    /// Các bộ sticker máy chủ đã tải sẵn thành GIF động, bộ dùng gần nhất trước (GET /api/sticker/kho).
    func khoSticker() async throws -> [BoSticker] {
        try await goiJSON("/api/sticker/kho")
    }

    /// Gửi 1 sticker (Zalo không cho trích dẫn kèm sticker).
    func guiSticker(cuoc: String, id: Int) async throws {
        struct Than: Encodable { let id: Int }
        _ = try await goi("/api/gui-sticker", method: "POST", query: ["cuoc": cuoc], jsonBody: Than(id: id))
    }

    // ---------------------------------------------------------------- thao tác trên 1 tin
    func thaCamXuc(cuoc: String, msg: String, icon: String) async throws {
        struct Than: Encodable { let icon: String }
        _ = try await goi("/api/cam-xuc", method: "POST", query: ["cuoc": cuoc, "msg": msg], jsonBody: Than(icon: icon))
    }

    func thuHoiTin(cuoc: String, msg: String) async throws {
        _ = try await goi("/api/thu-hoi", method: "POST", query: ["cuoc": cuoc, "msg": msg])
    }

    struct KetQuaChuyenTiep: Decodable { let ok: [String]; let loi: [ChiTietLoiChuyenTiep] }
    struct ChiTietLoiChuyenTiep: Decodable { let id: String?; let ten: String?; let loi: String? }

    /// v7.6: `album` = mọi msgId của 1 album (nhiều ảnh gửi 1 lần) -> máy chủ gửi lại thành 1 album; trước chỉ đi ảnh đầu.
    func chuyenTiep(cuoc: String, msg: String, den: [String], loiNhan: String = "", album: [String] = []) async throws -> KetQuaChuyenTiep {
        struct Than: Encodable { let den: [String]; let loiNhan: String; let album: [String]? }
        return try await goiJSON("/api/chuyen-tiep", method: "POST", query: ["cuoc": cuoc, "msg": msg],
                                  jsonBody: Than(den: den, loiNhan: loiNhan, album: album.count > 1 ? album : nil))
    }

    // ---------------------------------------------------------------- ghim / tắt thông báo / danh bạ
    struct KetQuaGhim: Decodable { let ghim: Int? }
    func datGhim(cuoc: String, bat: Bool) async throws -> KetQuaGhim {
        struct Than: Encodable { let ghim: Bool }
        return try await goiJSON("/api/ghim", method: "POST", query: ["cuoc": cuoc], jsonBody: Than(ghim: bat))
    }

    // ---------------------------------------------------------------- nhóm phân loại tùy chọn (/api/nhom-tuy-chon)
    func layNhomTuyChon() async throws -> [NhomTuyChon] {
        try await goiJSON("/api/nhom-tuy-chon")
    }

    func luuNhomTuyChon(_ ds: [NhomTuyChon]) async throws {
        _ = try await goi("/api/nhom-tuy-chon", method: "POST", jsonBody: ds)
    }

    // ---------------------------------------------------------------- tin nhắn đã ghim (tin_ghim)
    func layDsTinGhim(cuoc: String) async throws -> [TinGhim] {
        try await goiJSON("/api/tin-ghim", query: ["cuoc": cuoc])
    }

    func datTinGhim(cuoc: String, msgId: String, ghim: Bool, tieuDe: String = "") async throws -> [TinGhim] {
        struct Than: Encodable {
            let msgId: String
            let ghim: Bool
            let tieuDe: String
        }
        struct KetQua: Decodable {
            let ok: Bool
            let cuocId: String
            let dsGhim: [TinGhim]
        }
        let kq: KetQua = try await goiJSON("/api/tin-ghim", method: "POST", query: ["cuoc": cuoc, "msg": msgId], jsonBody: Than(msgId: msgId, ghim: ghim, tieuDe: tieuDe))
        return kq.dsGhim
    }

    func datTatThongBao(cuoc: String, tat: Bool) async throws {
        struct Than: Encodable { let tat: Bool }
        _ = try await goi("/api/tat-thong-bao", method: "POST", query: ["cuoc": cuoc], jsonBody: Than(tat: tat))
    }

    struct KetQuaDanhBa: Decodable { let ok: Bool; let so: Int? }
    func lamMoiDanhBa() async throws -> KetQuaDanhBa {
        try await goiJSON("/api/danh-ba", method: "POST")
    }

    // ---------------------------------------------------------------- bình chọn nhóm (poll)
    func layChiTietBinhChon(pollId: String) async throws -> BinhChonInfo {
        return try await goiJSON("/api/binh-chon", query: ["id": pollId])
    }

    func boPhieuBinhChon(pollId: String, cuocId: String, optionIds: [Int]) async throws -> BinhChonInfo {
        struct Than: Encodable { let optionIds: [Int] }
        return try await goiJSON("/api/binh-chon", method: "POST", query: ["id": pollId, "cuoc": cuocId], jsonBody: Than(optionIds: optionIds))
    }

    // ---------------------------------------------------------------- đặt lịch hẹn (nhắc hẹn)
    struct ThamSoTaoLich: Encodable {
        let tieuDe: String
        let batDau: Int64
        let lap: Int
        let emoji: String
        let chiaSe: Bool
    }

    struct KetQuaTaoLich: Decodable {
        let id: String?
        let tieuDe: String?
        let batDau: Int64?
        let emoji: String?
        let dienThoai: Bool?
    }

    @discardableResult
    func taoLichHen(cuoc: String, tieuDe: String, batDau: Int64, lap: Int = 0, emoji: String = "⏰", chiaSe: Bool = true) async throws -> KetQuaTaoLich {
        let body = ThamSoTaoLich(tieuDe: tieuDe, batDau: batDau, lap: lap, emoji: emoji, chiaSe: chiaSe)
        return try await goiJSON("/api/lich", method: "POST", query: ["cuoc": cuoc], jsonBody: body)
    }

    func xoaLichHen(cuoc: String, id: String) async throws {
        _ = try await goi("/api/lich/xoa", method: "POST", query: ["cuoc": cuoc, "id": id])
    }

    func giaTriCookiePhien() -> String? {
        if let v = UserDefaults.standard.string(forKey: "zl_session_zw"), !v.isEmpty {
            return v
        }
        if let c = (HTTPCookieStorage.shared.cookies(for: baseURL) ?? []).first(where: { $0.name == "zw" }) {
            return c.value
        }
        if let all = HTTPCookieStorage.shared.cookies, let c = all.first(where: { $0.name == "zw" }) {
            return c.value
        }
        return nil
    }

    // ---------------------------------------------------------------- địa chỉ media (ảnh/file/video đã lưu)
    // Khớp mediaUrl() trong web/index.html: "/media/" + file (đổi \ -> /, bỏ tiền tố "media/" nếu có, mã hoá từng đoạn)
    func diaChiMedia(_ file: String, tai: String? = nil, xem: String? = nil) -> URL? {
        var chuan = file.replacingOccurrences(of: "\\", with: "/")
        if chuan.hasPrefix("media/") { chuan.removeFirst("media/".count) }
        let phan = chuan.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
        var query = ["tai": tai, "ten": xem]
        if let zw = giaTriCookiePhien() { query["zw"] = zw }
        guard let u = try? url("/media/" + phan.joined(separator: "/"), query: query) else { return nil }
        return u
    }

    /// URL kèm cookie phiên (để tải file nhị phân qua URLSession.shared.download, hoặc dùng SSE endpoint)
    func diaChiSuKien() throws -> URL {
        var query: [String: String?] = [:]
        if let zw = giaTriCookiePhien() { query["zw"] = zw }
        return try url("/api/su-kien", query: query)
    }

    // ---------------------------------------------------------------- điều khiển cuộc gọi Zalo PC
    func traLoiCuocGoi() async throws {
        _ = try await goi("/api/cuoc-goi/tra-loi", method: "POST")
    }

    func tuChoiCuocGoi() async throws {
        _ = try await goi("/api/cuoc-goi/tu-choi", method: "POST")
    }

    // ---------------------------------------------------------------- trạng thái & đăng nhập Zalo Web máy chủ
    func layTrangThaiZalo() async throws -> ZaloServerStatus {
        try await goiJSON("/api/zalo/trang-thai")
    }

    func yeuCauDangNhapZalo() async throws -> ZaloServerStatus {
        try await goiJSON("/api/zalo/dang-nhap", method: "POST")
    }

    func huyDangNhapZalo() async throws {
        _ = try await goi("/api/zalo/huy-qr", method: "POST")
    }
}

// Hộp bọc để JSONEncoder nhận Encodable kiểu tồn tại (existential) mà vẫn encode đúng kiểu cụ thể bên trong.
private struct AnyEncodableBox: Encodable {
    let gia_tri: Encodable
    init(_ g: Encodable) { gia_tri = g }
    func encode(to encoder: Encoder) throws { try gia_tri.encode(to: encoder) }
}
