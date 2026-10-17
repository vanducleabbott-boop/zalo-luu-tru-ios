// Gọi các route của web_zalo.mjs (xem file đó + web/index.html để đối chiếu tham số/định dạng).
// Phiên đăng nhập = 1 cookie "zw=..." lưu trong HTTPCookieStorage.shared (persist qua lần mở app).

import Foundation

enum LoiZaloAPI: Error, LocalizedError {
    case chuaDangNhap
    case maHttp(Int, String)
    case diaChiKhongHopLe

    var errorDescription: String? {
        switch self {
        case .chuaDangNhap: return "Hết phiên đăng nhập"
        case .maHttp(let ma, let loi): return loi.isEmpty ? "Lỗi máy chủ (\(ma))" : loi
        case .diaChiKhongHopLe: return "Địa chỉ máy chủ không hợp lệ"
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
                      jsonBody: Encodable? = nil, rawBody: Data? = nil, headers: [String: String] = [:]) async throws -> Data {
        var req = URLRequest(url: try url(duongDan, query: query))
        req.httpMethod = method
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let jsonBody {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(AnyEncodableBox(jsonBody))
        } else if let rawBody {
            req.httpBody = rawBody
        }
        let (data, resp) = try await session.data(for: req)
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
    /// true = đúng mật khẩu (cookie đã lưu vào HTTPCookieStorage.shared); false = sai mật khẩu.
    func dangNhap(matKhau: String) async throws -> Bool {
        var req = URLRequest(url: try url("/dang-nhap"))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = "mk=" + (matKhau.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        req.httpBody = form.data(using: .utf8)
        let (_, resp) = try await session.data(for: req, delegate: khongChuyenHuong)
        guard let http = resp as? HTTPURLResponse else { return false }
        return http.statusCode == 303
    }

    func dangXuat() {
        for c in HTTPCookieStorage.shared.cookies(for: baseURL) ?? [] { HTTPCookieStorage.shared.deleteCookie(c) }
    }

    func daCoCookiePhien() -> Bool {
        (HTTPCookieStorage.shared.cookies(for: baseURL) ?? []).contains { $0.name == "zw" }
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
                           rawBody: duLieu, headers: ["X-Ten-File": tenMaHoa])
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

    func chuyenTiep(cuoc: String, msg: String, den: [String], loiNhan: String = "") async throws -> KetQuaChuyenTiep {
        struct Than: Encodable { let den: [String]; let loiNhan: String }
        return try await goiJSON("/api/chuyen-tiep", method: "POST", query: ["cuoc": cuoc, "msg": msg],
                                  jsonBody: Than(den: den, loiNhan: loiNhan))
    }

    // ---------------------------------------------------------------- ghim / tắt thông báo / danh bạ
    struct KetQuaGhim: Decodable { let ghim: Int? }
    func datGhim(cuoc: String, bat: Bool) async throws -> KetQuaGhim {
        struct Than: Encodable { let ghim: Bool }
        return try await goiJSON("/api/ghim", method: "POST", query: ["cuoc": cuoc], jsonBody: Than(ghim: bat))
    }

    func datTatThongBao(cuoc: String, tat: Bool) async throws {
        struct Than: Encodable { let tat: Bool }
        _ = try await goi("/api/tat-thong-bao", method: "POST", query: ["cuoc": cuoc], jsonBody: Than(tat: tat))
    }

    struct KetQuaDanhBa: Decodable { let ok: Bool; let so: Int? }
    func lamMoiDanhBa() async throws -> KetQuaDanhBa {
        try await goiJSON("/api/danh-ba", method: "POST")
    }

    func giaTriCookiePhien() -> String? {
        (HTTPCookieStorage.shared.cookies(for: baseURL) ?? []).first { $0.name == "zw" }?.value
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
    func diaChiSuKien() throws -> URL { try url("/api/su-kien") }
}

// Hộp bọc để JSONEncoder nhận Encodable kiểu tồn tại (existential) mà vẫn encode đúng kiểu cụ thể bên trong.
private struct AnyEncodableBox: Encodable {
    let gia_tri: Encodable
    init(_ g: Encodable) { gia_tri = g }
    func encode(to encoder: Encoder) throws { try gia_tri.encode(to: encoder) }
}
