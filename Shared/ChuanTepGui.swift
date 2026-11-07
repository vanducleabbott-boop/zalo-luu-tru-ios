// v7.12 (07/11/2026): chuẩn tệp trước khi gửi Zalo (dùng chung app + tiện ích Chia sẻ).
// - Ảnh HEIC/HEIF/AVIF/TIFF/BMP -> luôn đổi JPEG, cạnh dài <= 2560 (Zalo người nhận không mở được HEIC).
// - Ảnh JPEG/PNG/WebP > 1,5 MB -> thu về 2560 (ảnh gốc 4-10 MB qua 5G + Cloudflare hay đứt).
// - Video không phải MP4 (MOV/HEVC...) -> MP4 H.264 720p.
// Dùng ImageIO tạo ảnh thu nhỏ thẳng từ tệp (không giải mã ảnh 48MP đầy đủ -> tiện ích Chia sẻ không bị iOS giết vì
// quá bộ nhớ), tự xoay đúng chiều theo EXIF. Đổi lỗi -> giữ tệp gốc (máy chủ có ffmpeg đổi tiếp).

import Foundation
import UIKit
import ImageIO
import AVFoundation

enum ChuanTepGui {
    static let duoiAnhPhaiDoi: Set<String> = ["heic", "heif", "hif", "avif", "tif", "tiff", "bmp"]
    static let duoiAnhCoTheNho: Set<String> = ["jpg", "jpeg", "png", "webp"]
    static let duoiVideoPhaiDoi: Set<String> = ["mov", "qt", "m4v", "3gp", "avi", "mkv", "webm", "hevc"]
    static let nguongThuNho = 1_500_000

    static func kichThuoc(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    /// JPEG cạnh dài <= canhToiDa từ nguồn ảnh. boQuaNeuTrongSuot: PNG/WebP có alpha thì không đổi (JPEG ra nền đen).
    static func jpeg(tuNguon src: CGImageSource, canhToiDa: Int = 2560, boQuaNeuTrongSuot: Bool = false) -> Data? {
        let tuyChon: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: canhToiDa,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, tuyChon as CFDictionary) else { return nil }
        if boQuaNeuTrongSuot {
            switch cg.alphaInfo {
            case .first, .last, .premultipliedFirst, .premultipliedLast: return nil
            default: break
            }
        }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.8)
    }

    static func jpeg(tuTep url: URL, boQuaNeuTrongSuot: Bool = false) -> Data? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return jpeg(tuNguon: src, boQuaNeuTrongSuot: boQuaNeuTrongSuot)
    }

    static func jpeg(tuDuLieu data: Data, boQuaNeuTrongSuot: Bool = false) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return jpeg(tuNguon: src, boQuaNeuTrongSuot: boQuaNeuTrongSuot)
    }

    /// Xuất MP4 H.264 720p (hoặc chất lượng vừa). Lỗi -> nil.
    static func mp4(_ url: URL) async -> URL? {
        let asset = AVURLAsset(url: url)
        let preset = AVAssetExportSession.exportPresets(compatibleWith: asset).contains(AVAssetExportPreset1280x720)
            ? AVAssetExportPreset1280x720 : AVAssetExportPresetMediumQuality
        guard let xs = AVAssetExportSession(asset: asset, presetName: preset) else { return nil }
        let ra = url.deletingLastPathComponent().appendingPathComponent("chuan_\(UUID().uuidString).mp4")
        xs.outputURL = ra
        xs.outputFileType = .mp4
        xs.shouldOptimizeForNetworkUse = true
        await xs.export()
        return xs.status == .completed ? ra : nil
    }

    /// Chuẩn 1 tệp trên đĩa. Trả về tệp mới (tệp gốc bị xoá) hoặc chính tệp gốc nếu không cần/không đổi được.
    static func chuan(url: URL, ten: String) async -> (url: URL, ten: String) {
        let duoi = (ten as NSString).pathExtension.lowercased()
        var goc = (ten as NSString).deletingPathExtension
        if goc.isEmpty { goc = "tep" }
        let thuMuc = url.deletingLastPathComponent()
        let phaiDoi = duoiAnhPhaiDoi.contains(duoi)
        if phaiDoi || (duoiAnhCoTheNho.contains(duoi) && kichThuoc(url) > nguongThuNho) {
            guard let data = jpeg(tuTep: url, boQuaNeuTrongSuot: !phaiDoi) else { return (url, ten) }
            if !phaiDoi && data.count >= kichThuoc(url) { return (url, ten) }
            let ra = thuMuc.appendingPathComponent(UUID().uuidString + "_" + goc + ".jpg")
            do {
                try data.write(to: ra)
                try? FileManager.default.removeItem(at: url)
                return (ra, goc + ".jpg")
            } catch { return (url, ten) }
        }
        if duoiVideoPhaiDoi.contains(duoi), let ra = await mp4(url) {
            try? FileManager.default.removeItem(at: url)
            return (ra, goc + ".mp4")
        }
        return (url, ten)
    }
}
