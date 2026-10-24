// Bộ nhớ đệm tin nhắn cục bộ (TinNhanDiskCache):
// Lưu trữ tin nhắn (text, metadata) của các cuộc hội thoại trên iPhone dưới dạng JSON gọn nhẹ.
// Giúp hiển thị tức thì (0ms) ngay khi bấm vào chat, không cần chờ mạng tải lại.
// Hỗ trợ cập nhật realtime khi có tin mới và tự động dọn dẹp các cuộc trò chuyện cũ hơn 1 tháng.

import Foundation

final class TinNhanDiskCache {
    static let shared = TinNhanDiskCache()

    private let fileManager = FileManager.default
    private let thuMucCache: URL
    private let khoaLock = NSLock()
    private let motThangGiay: TimeInterval = 30 * 24 * 3600 // 30 ngày

    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        thuMucCache = caches.appendingPathComponent("ZaloMessageCache", isDirectory: true)

        if !fileManager.fileExists(atPath: thuMucCache.path) {
            try? fileManager.createDirectory(at: thuMucCache, withIntermediateDirectories: true)
        }

        Task(priority: .background) { [weak self] in
            self?.donDepTinCu()
        }
    }

    private func duongDanFile(cho cuocId: String) -> URL {
        let tenHopLe = cuocId.replacingOccurrences(of: "/", with: "_")
                             .replacingOccurrences(of: ":", with: "_")
        return thuMucCache.appendingPathComponent("\(tenHopLe).json")
    }

    /// Lấy danh sách tin nhắn đã lưu trong bộ nhớ máy của 1 cuộc hội thoại
    func layTin(cuocId: String) -> [Tin]? {
        let f = duongDanFile(cho: cuocId)
        khoaLock.lock()
        defer { khoaLock.unlock() }

        guard fileManager.fileExists(atPath: f.path),
              let data = try? Data(contentsOf: f) else { return nil }

        // Cập nhật ngày truy cập để không bị dọn dẹp sớm
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: f.path)
        return try? JSONDecoder().decode([Tin].self, from: data)
    }

    /// Lưu danh sách tin nhắn vào bộ nhớ máy
    func luuTin(_ tin: [Tin], cuocId: String) {
        guard !tin.isEmpty else { return }
        let f = duongDanFile(cho: cuocId)
        khoaLock.lock()
        defer { khoaLock.unlock() }

        do {
            let data = try JSONEncoder().encode(tin)
            try data.write(to: f, options: .atomic)
        } catch {
            print("[TinNhanDiskCache] Loi ghi cache tin cuoc \(cuocId):", error.localizedDescription)
        }
    }

    /// Cập nhật thêm 1 tin nhắn mới (realtime SSE) vào cache
    func capNhatTinMoi(tin: Tin, cuocId: String) {
        let f = duongDanFile(cho: cuocId)
        khoaLock.lock()
        defer { khoaLock.unlock() }

        var hienTai: [Tin] = []
        if fileManager.fileExists(atPath: f.path),
           let data = try? Data(contentsOf: f),
           let ds = try? JSONDecoder().decode([Tin].self, from: data) {
            hienTai = ds
        }

        // Kiểm tra tránh trùng tin
        if let idx = hienTai.firstIndex(where: { $0.msgId == tin.msgId }) {
            hienTai[idx] = tin
        } else {
            hienTai.append(tin)
            // Giữ tối đa 120 tin gần nhất trong cache nhanh
            if hienTai.count > 120 {
                hienTai = Array(hienTai.suffix(120))
            }
        }

        if let data = try? JSONEncoder().encode(hienTai) {
            try? data.write(to: f, options: .atomic)
        }
    }

    /// v5.4: tìm KHÔNG DẤU trong các tin đã lưu trên máy (máy chủ chỉ tìm đúng dấu: "Han" không ra "Hạnh").
    /// cuocId = nil -> tìm mọi cuộc. Trả về (mã cuộc, tin), mới nhất trước.
    func timTin(_ tuKhoa: String, cuocId: String? = nil, toiDa: Int = 100) -> [(cuocId: String, tin: Tin)] {
        let q = tuKhoa.trimmingCharacters(in: .whitespacesAndNewlines).boDau
        guard !q.isEmpty else { return [] }
        let dsFile: [URL]
        if let cuocId { dsFile = [duongDanFile(cho: cuocId)] }
        else { dsFile = (try? fileManager.contentsOfDirectory(at: thuMucCache, includingPropertiesForKeys: nil)) ?? [] }
        var kq: [(cuocId: String, tin: Tin)] = []
        for f in dsFile where f.pathExtension == "json" {
            khoaLock.lock()
            let data = try? Data(contentsOf: f)
            khoaLock.unlock()
            guard let data, let ds = try? JSONDecoder().decode([Tin].self, from: data) else { continue }
            let id = cuocId ?? f.deletingPathExtension().lastPathComponent
            for t in ds where !t.msgId.hasPrefix("temp_") {
                if [t.chu, t.tenFile].contains(where: { $0?.boDau.contains(q) == true }) { kq.append((t.cuocId ?? id, t)) }
            }
        }
        return Array(kq.sorted { $0.tin.ts > $1.tin.ts }.prefix(toiDa))
    }

    /// Dọn dẹp cache của các cuộc hội thoại không tương tác quá 30 ngày
    func donDepTinCu() {
        let moc30Ngay = Date().addingTimeInterval(-motThangGiay)
        guard let files = try? fileManager.contentsOfDirectory(
            at: thuMucCache,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        for file in files {
            if let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               date < moc30Ngay {
                khoaLock.lock()
                try? fileManager.removeItem(at: file)
                khoaLock.unlock()
            }
        }
    }

    /// Xóa toàn bộ tin nhắn đã lưu trên máy
    func xoaToanBo() {
        khoaLock.lock()
        defer { khoaLock.unlock() }
        try? fileManager.removeItem(at: thuMucCache)
        try? fileManager.createDirectory(at: thuMucCache, withIntermediateDirectories: true)
    }
}
