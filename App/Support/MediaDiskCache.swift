// Bộ nhớ đệm đĩa cục bộ trên iPhone (MediaDiskCache):
// Tự động lưu trữ ảnh, video và tệp tin của các hội thoại trong vòng 1 tháng (30 ngày) trên bộ nhớ iPhone.
// Giúp hiển thị tức thì (0ms mạng), không cần tải lại nhiều lần.
// Sử dụng khoá đệm chuẩn hoá (loại bỏ tham số zw/phiên) để cache luôn bền vững.
// Hàng đợi MediaPrefetchQueue điều phối tải ngầm ưu tiên vừa phải, không nghẽn mạng UI.

import Foundation
import UIKit

final class MediaDiskCache {
    static let shared = MediaDiskCache()

    private let fileManager = FileManager.default
    private let thuMucCache: URL
    private let motTuanGiay: TimeInterval = 7 * 24 * 3600   // 7 ngày (1 tuần) cho tệp tin tài liệu
    private let motThangGiay: TimeInterval = 30 * 24 * 3600 // 30 ngày (1 tháng) cho ảnh và video
    private let khoaLock = NSLock()
    private var dangTaiFileTasks: [String: Task<URL?, Never>] = [:]

    static let duoiAnhVideo: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "svg",
        "mp4", "mov", "m4v", "3gp", "avi"
    ]

    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        thuMucCache = caches.appendingPathComponent("ZaloMediaCache", isDirectory: true)

        if !fileManager.fileExists(atPath: thuMucCache.path) {
            try? fileManager.createDirectory(at: thuMucCache, withIntermediateDirectories: true)
        }

        // Tự động dọn dẹp các tệp quá hạn (file > 7 ngày, ảnh/video > 30 ngày)
        Task(priority: .background) { [weak self] in
            self?.donDepCacheCu()
        }
    }

    /// Khoá duy nhất dựa trên đường dẫn tài nguyên (bỏ qua query token zw để cache không bị vô hiệu hoá khi đổi phiên)
    func khoaCache(tu url: URL) -> String {
        let path = url.path
        var hash: UInt64 = 5381
        for byte in path.utf8 {
            hash = 127 * (hash & 0x00FFFFFFFFFFFFFF) + UInt64(byte)
        }
        return String(format: "%016llx", hash)
    }

    /// Tên file lưu trên đĩa kèm tên gốc và đuôi mở rộng chuẩn (Word, Excel, PPT, PDF...) để QuickLook nhận diện chính xác
    func tenFile(tu url: URL, tenGoc: String? = nil) -> String {
        let khoa = khoaCache(tu: url)
        var ext = ""
        var tenKhongExt = ""

        if var tg = tenGoc, !tg.isEmpty {
            if tg.lowercased().hasSuffix(".tai") {
                tg = String(tg.dropLast(4))
            }
            let nsTg = tg as NSString
            ext = nsTg.pathExtension.lowercased()
            tenKhongExt = nsTg.deletingPathExtension
        }

        if ext.isEmpty {
            var urlPath = url.path
            if urlPath.lowercased().hasSuffix(".tai") {
                urlPath = String(urlPath.dropLast(4))
            }
            let nsUrl = (urlPath as NSString).lastPathComponent as NSString
            ext = nsUrl.pathExtension.lowercased()
            if tenKhongExt.isEmpty {
                tenKhongExt = nsUrl.deletingPathExtension
            }
        }

        if ext.isEmpty || ext == "dat" {
            if url.path.contains("video") || url.absoluteString.contains("video") {
                ext = "mp4"
            } else {
                ext = "dat"
            }
        }

        // Loại bỏ ký tự đặc biệt nguy hiểm cho đường dẫn file iOS (đặc biệt #, %, ?, ...)
        let kyTuCam = CharacterSet(charactersIn: "/\\:?*\"<>|#%{}[]^`~")
        var tenSanitized = tenKhongExt.components(separatedBy: kyTuCam).joined(separator: "_")
        tenSanitized = String(tenSanitized.prefix(48)).trimmingCharacters(in: .whitespacesAndNewlines)
        if tenSanitized.isEmpty {
            tenSanitized = "file"
        }

        return "\(khoa)_\(tenSanitized).\(ext)"
    }

    func duongDanFile(cho url: URL, tenFile: String? = nil) -> URL {
        thuMucCache.appendingPathComponent(self.tenFile(tu: url, tenGoc: tenFile))
    }

    /// Lưu file tạm thời trên đĩa để hiển thị tức thì (optimistic preview)
    func luuMediaCucBo(data: Data, tenFile: String) -> URL {
        let ext = (tenFile as NSString).pathExtension
        let safeExt = ext.isEmpty ? "dat" : ext
        let f = thuMucCache.appendingPathComponent("opt_\(UUID().uuidString).\(safeExt)")
        try? data.write(to: f)
        return f
    }

    /// Tìm file cục bộ đã có trên máy
    func layFileCucBo(cho url: URL, tenFile: String? = nil) -> URL? {
        if url.isFileURL || url.scheme == "file" {
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        khoaLock.lock()
        defer { khoaLock.unlock() }

        // 1. Kiểm tra đường dẫn chính xác với tenFile
        let f = duongDanFile(cho: url, tenFile: tenFile)
        if fileManager.fileExists(atPath: f.path) {
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: f.path)
            return f
        }

        // 2. Nếu có tên file chỉ định nhưng chưa thấy, thử đường dẫn mặc định từ URL
        if tenFile != nil {
            let fDef = duongDanFile(cho: url, tenFile: nil)
            if fileManager.fileExists(atPath: fDef.path) {
                try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fDef.path)
                return fDef
            }
        }

        // 3. Quét nhanh theo tiền tố khoaCache trong thư mục đệm
        let khoa = khoaCache(tu: url)
        if let danhSach = try? fileManager.contentsOfDirectory(atPath: thuMucCache.path) {
            if let khop = danhSach.first(where: { $0.hasPrefix(khoa + "_") }) {
                let u = thuMucCache.appendingPathComponent(khop)
                try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: u.path)
                return u
            }
        }

        return nil
    }

    /// Kiểm tra file đã có trên đĩa iPhone chưa (không tốn mạng)
    func daCo(cho url: URL, tenFile: String? = nil) -> Bool {
        layFileCucBo(cho: url, tenFile: tenFile) != nil
    }

    /// Đọc dữ liệu từ đĩa iPhone
    func layDuLieu(cho url: URL, tenFile: String? = nil) -> Data? {
        guard let f = layFileCucBo(cho: url, tenFile: tenFile) else { return nil }
        khoaLock.lock()
        defer { khoaLock.unlock() }
        return try? Data(contentsOf: f)
    }

    /// Lưu dữ liệu ảnh/file vào đĩa iPhone
    func luuDuLieu(_ data: Data, cho url: URL, tenFile: String? = nil) {
        let f = duongDanFile(cho: url, tenFile: tenFile)
        khoaLock.lock()
        defer { khoaLock.unlock() }
        try? data.write(to: f, options: .atomic)
    }

    /// Tải tệp tin (ảnh/tệp đính kèm) và lưu vào bộ nhớ iPhone
    func taiVaLuuFile(tu url: URL, tenFile: String? = nil) async -> URL? {
        if let daCo = layFileCucBo(cho: url, tenFile: tenFile) { return daCo }

        let khoa = khoaCache(tu: url) + (tenFile ?? "")
        khoaLock.lock()
        if let taskDangChay = dangTaiFileTasks[khoa] {
            khoaLock.unlock()
            return await taskDangChay.value
        }

        let task = Task<URL?, Never> { [weak self, url, tenFile, khoa] in
            guard let self = self else { return nil }
            let dich = self.duongDanFile(cho: url, tenFile: tenFile)
            do {
                var req = URLRequest(url: url)
                CloudflareAccess.apply(to: &req)
                req.timeoutInterval = 60
                let (tam, resp) = try await URLSession.shared.download(for: req)
                if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    try? self.fileManager.removeItem(at: tam)
                    return nil
                }
                self.khoaLock.lock()
                defer { self.khoaLock.unlock() }
                try? self.fileManager.removeItem(at: dich)
                try self.fileManager.moveItem(at: tam, to: dich)
                return dich
            } catch {
                return nil
            }
        }

        dangTaiFileTasks[khoa] = task
        khoaLock.unlock()

        let ketQua = await task.value

        khoaLock.lock()
        dangTaiFileTasks.removeValue(forKey: khoa)
        khoaLock.unlock()

        return ketQua
    }

    /// Tải video về lưu đĩa iPhone để xem offline và xem tức thì
    func taiVaLuuVideo(tu url: URL) async -> URL? {
        let ext = (url.pathExtension.isEmpty || url.pathExtension.lowercased() == "dat") ? "mp4" : url.pathExtension
        let tenGoc = (url.lastPathComponent as NSString).deletingPathExtension
        let ten = "\(tenGoc.isEmpty ? "video" : tenGoc).\(ext)"
        return await taiVaLuuFile(tu: url, tenFile: ten)
    }

    /// Tải trước ảnh hoặc video ở chế độ ngầm nếu trong vòng 1 tháng
    func taiTruoc(url: URL) {
        guard !daCo(cho: url) else { return }
        Task(priority: .background) {
            await MediaPrefetchQueue.shared.them(urls: [url])
        }
    }

    /// Tính tổng dung lượng thư mục đệm đang dùng
    func tinhDungLuongCache() -> Int64 {
        guard let tepTins = try? fileManager.contentsOfDirectory(
            at: thuMucCache,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        var tong: Int64 = 0
        for f in tepTins {
            if let size = (try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                tong += Int64(size)
            }
        }
        return tong
    }

    /// Chuỗi định dạng dung lượng dễ đọc (VD: "24.5 MB")
    func dungLuongDinhDang() -> String {
        let bytes = tinhDungLuongCache()
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024)
        }
        return String(format: "%.1f MB", mb)
    }

    /// Xoá toàn bộ bộ nhớ đệm
    func xoaToanBoCache() {
        khoaLock.lock()
        defer { khoaLock.unlock() }
        try? fileManager.removeItem(at: thuMucCache)
        try? fileManager.createDirectory(at: thuMucCache, withIntermediateDirectories: true)
    }

    /// Dọn dẹp các tệp đã lưu quá hạn:
    /// - File tài liệu: tự động xóa sau 7 ngày (1 tuần)
    /// - Ảnh và video: tự động xóa sau 30 ngày (1 tháng)
    func donDepCacheCu() {
        let moc7Ngay = Date().addingTimeInterval(-motTuanGiay)
        let moc30Ngay = Date().addingTimeInterval(-motThangGiay)
        guard let tepTins = try? fileManager.contentsOfDirectory(
            at: thuMucCache,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        for file in tepTins {
            let ext = file.pathExtension.lowercased()
            let laAnhVideo = MediaDiskCache.duoiAnhVideo.contains(ext)
            let mocXoa = laAnhVideo ? moc30Ngay : moc7Ngay

            if let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               date < mocXoa {
                khoaLock.lock()
                try? fileManager.removeItem(at: file)
                khoaLock.unlock()
            }
        }
    }
}

// ---------------------------------------------------------------- Hàng đợi tải trước thông minh (MediaPrefetchQueue)
// Điều phối tải trước tối đa 2 tệp cùng lúc ở background, không chiếm đường truyền của giao diện chính
actor MediaPrefetchQueue {
    static let shared = MediaPrefetchQueue()

    private var dangTai = Set<String>()
    private var hangDoi: [URL] = []
    private let maxDongThoi = 2
    private var dangChay = 0

    func them(urls: [URL]) {
        for u in urls {
            let k = MediaDiskCache.shared.khoaCache(tu: u)
            guard !MediaDiskCache.shared.daCo(cho: u), !dangTai.contains(k), !hangDoi.contains(u) else { continue }
            hangDoi.append(u)
        }
        kichHoatTiep()
    }

    private func kichHoatTiep() {
        while dangChay < maxDongThoi && !hangDoi.isEmpty {
            let url = hangDoi.removeFirst()
            let k = MediaDiskCache.shared.khoaCache(tu: url)
            guard !MediaDiskCache.shared.daCo(cho: url) else { continue }

            dangTai.insert(k)
            dangChay += 1

            Task(priority: .background) { [weak self] in
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    MediaDiskCache.shared.luuDuLieu(data, cho: url)
                } catch {}
                await self?.hoanTat(k)
            }
        }
    }

    private func hoanTat(_ khoa: String) {
        dangTai.remove(khoa)
        dangChay = max(0, dangChay - 1)
        kichHoatTiep()
    }

    func xoaHangDoi() {
        hangDoi.removeAll()
    }
}
