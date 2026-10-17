// Bộ nhớ đệm đĩa cục bộ trên iPhone (MediaDiskCache):
// Tự động lưu trữ ảnh và video của các hội thoại trong vòng 1 tháng (30 ngày) trên bộ nhớ iPhone.
// Giúp hiển thị và phát video tức thì, không cần tải lại qua mạng.
// Tự động dọn dẹp các tệp cũ hơn 30 ngày.

import Foundation
import UIKit

final class MediaDiskCache {
    static let shared = MediaDiskCache()

    private let fileManager = FileManager.default
    private let thuMucCache: URL
    private let motThangGiay: TimeInterval = 30 * 24 * 3600 // 30 ngày
    private let khoaLock = NSLock()

    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        thuMucCache = caches.appendingPathComponent("ZaloMediaCache", isDirectory: true)

        if !fileManager.fileExists(atPath: thuMucCache.path) {
            try? fileManager.createDirectory(at: thuMucCache, withIntermediateDirectories: true)
        }

        // Tự động dọn dẹp các file cũ hơn 1 tháng khi khởi tạo
        Task(priority: .background) { [weak self] in
            self?.donDepCacheCu()
        }
    }

    /// Tạo tên file duy nhất từ URL
    func tenFile(tu url: URL) -> String {
        let path = url.path
        let chuoi = url.absoluteString
        var hash: UInt64 = 5381
        for byte in chuoi.utf8 {
            hash = 127 * (hash & 0x00FFFFFFFFFFFFFF) + UInt64(byte)
        }
        let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
        let tenGoc = (url.lastPathComponent as NSString).deletingPathExtension
        let tenRutGon = String(tenGoc.prefix(16)).replacingOccurrences(of: "/", with: "_")
        return "\(String(format: "%016llx", hash))_\(tenRutGon).\(ext)"
    }

    func duongDanFile(cho url: URL) -> URL {
        thuMucCache.appendingPathComponent(tenFile(tu: url))
    }

    /// Kiểm tra file đã có trên đĩa chưa
    func daCo(cho url: URL) -> Bool {
        let f = duongDanFile(cho: url)
        return fileManager.fileExists(atPath: f.path)
    }

    /// Đọc dữ liệu từ đĩa iPhone (0ms mạng)
    func layDuLieu(cho url: URL) -> Data? {
        let f = duongDanFile(cho: url)
        guard fileManager.fileExists(atPath: f.path) else { return nil }
        khoaLock.lock()
        defer { khoaLock.unlock() }
        // Cập nhật ngày truy cập (touch) để duy trì thời hạn 30 ngày
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: f.path)
        return try? Data(contentsOf: f)
    }

    /// Lưu dữ liệu ảnh/file vào đĩa iPhone
    func luuDuLieu(_ data: Data, cho url: URL) {
        let f = duongDanFile(cho: url)
        khoaLock.lock()
        defer { khoaLock.unlock() }
        try? data.write(to: f, options: .atomic)
    }

    /// Trả về file URL cục bộ nếu video/file đã có trên đĩa
    func layFileCucBo(cho url: URL) -> URL? {
        let f = duongDanFile(cho: url)
        if fileManager.fileExists(atPath: f.path) {
            khoaLock.lock()
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: f.path)
            khoaLock.unlock()
            return f
        }
        return nil
    }

    /// Tải video về lưu đĩa iPhone để xem offline và xem tức thì
    func taiVaLuuVideo(tu url: URL) async -> URL? {
        if let daCo = layFileCucBo(cho: url) { return daCo }
        let dich = duongDanFile(cho: url)
        do {
            let (tam, _) = try await URLSession.shared.download(from: url)
            khoaLock.lock()
            defer { khoaLock.unlock() }
            try? fileManager.removeItem(at: dich)
            try fileManager.moveItem(at: tam, to: dich)
            return dich
        } catch {
            return nil
        }
    }

    /// Tải trước ảnh hoặc video ở chế độ ngầm nếu trong vòng 1 tháng
    func taiTruoc(url: URL) {
        guard !daCo(cho: url) else { return }
        Task(priority: .background) {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                self.luuDuLieu(data, cho: url)
            } catch {}
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

    /// Dọn dẹp các tệp đã lưu quá 30 ngày (1 tháng)
    func donDepCacheCu() {
        let moc30Ngay = Date().addingTimeInterval(-motThangGiay)
        guard let tepTins = try? fileManager.contentsOfDirectory(
            at: thuMucCache,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        for file in tepTins {
            if let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               date < moc30Ngay {
                khoaLock.lock()
                try? fileManager.removeItem(at: file)
                khoaLock.unlock()
            }
        }
    }
}
