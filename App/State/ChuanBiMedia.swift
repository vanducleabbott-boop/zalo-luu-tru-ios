// v8.3 (07/11/2026): chuẩn bị ảnh/video chọn từ thư viện NGAY TRONG việc tải nền (HangTaiLen).
// Trước: đọc + đổi video sang MP4 chạy trong màn hình nhập tin, xong mới chèn ô vào chat -> đổi video (vài chục giây)
// mà rời chat là mất, trong chat không thấy gì. Giờ ô video hiện ngay khi chọn, đổi định dạng + tải lên chạy nền.
// Máy chủ cắt ở 100MB -> chặn tệp > 95MB ngay ở máy (nén lại video, không được thì báo lỗi), tránh vòng thử lại vô hạn.

import Foundation
import SwiftUI
import UIKit
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

enum LoiMedia: LocalizedError {
    case khongDoc
    case quaLon
    case khongNen
    case anhQuaLon
    var errorDescription: String? {
        switch self {
        case .khongDoc: return "không đọc được ảnh/video từ thư viện (ảnh iCloud chưa tải về máy?)"
        case .quaLon: return "video quá dài (trên khoảng 35 phút), không nén được dưới 95 MB, hãy cắt ngắn video"
        case .khongNen: return "không nén được video này và tệp gốc trên 95 MB, hãy thử lại hoặc cắt ngắn video"
        case .anhQuaLon: return "tệp quá lớn (trên 95 MB)"
        }
    }
}

enum ChuanBiMedia {
    /// Giới hạn gửi (máy chủ cắt ở 100MB).
    static let gioiHan = 95_000_000

    static func laVideo(_ item: PhotosPickerItem) -> Bool {
        item.supportedContentTypes.contains {
            $0.conforms(to: .movie) || $0.conforms(to: .video) || $0.conforms(to: .quickTimeMovie) || $0.conforms(to: .mpeg4Movie)
        }
    }

    /// Đọc 1 mục từ thư viện, đổi sang dạng Zalo xem được:
    /// - Video (MOV/HEVC/H.265, kể cả HEVC đựng trong .mp4) -> luôn nén lại MP4 H.264 <= 1280, 30fps, dưới 90MB.
    /// - Ảnh (HEIC...) -> JPG cạnh dài <= 2560; GIF giữ nguyên.
    /// Ném LoiMedia nếu không đọc được / quá lớn. `tenGoc` là tên đã đặt cho ô tạm (đuôi .mp4 / .jpg).
    static func chuanBi(_ item: PhotosPickerItem, tenGoc: String) async throws -> (duLieu: Data, tenFile: String) {
        let goc = (tenGoc as NSString).deletingPathExtension
        if laVideo(item) {
            // 1. lấy tệp video gốc (MovieFile; hỏng thì lấy Data rồi ghi ra tệp tạm)
            var nguonTho: URL? = (try? await item.loadTransferable(type: MovieFile.self))?.url
            if nguonTho == nil, let d = try? await item.loadTransferable(type: Data.self) {
                let ext = item.supportedContentTypes.first(where: { $0.conforms(to: .movie) })?.preferredFilenameExtension ?? "mov"
                let u = FileManager.default.temporaryDirectory.appendingPathComponent("picked_\(UUID().uuidString).\(ext)")
                if (try? d.write(to: u)) != nil { nguonTho = u }
            }
            guard let nguon = nguonTho else { throw LoiMedia.khongDoc }
            defer { try? FileManager.default.removeItem(at: nguon) }
            // 2. v8.4: nén theo đúng dung lượng (H.264 <= 1280, 30fps, bitrate tính theo thời lượng). Lỗi (nhất là khi app ở nền)
            // -> chờ app active lại rồi thử lại, tối đa 2 lần thử lại
            var nenQuaDai = false
            var lanThuLai = 0
            while true {
                do {
                    let d = try await VideoHelper.nenTheoDungLuong(from: nguon, gioiHanByte: 90_000_000)
                    if d.count <= gioiHan { return (d, goc + ".mp4") }
                    break
                } catch {
                    if error is CancellationError { throw error }
                    let e = error as NSError
                    if e.domain == "VideoHelper", e.code == VideoHelper.maLoiQuaDai { nenQuaDai = true; break }
                    guard lanThuLai < 2 else { break }
                    lanThuLai += 1
                    let khongActive = await MainActor.run { UIApplication.shared.applicationState != .active }
                    if khongActive { await HangTaiLen.shared.choVaoLaiApp() }
                    try Task.checkCancellation()
                }
            }
            // quá dài -> chỉ còn cách thử chất lượng thấp nhất của hệ thống
            if nenQuaDai {
                try Task.checkCancellation()
                if let d = try? await VideoHelper.chuyenSangMP4(from: nguon, preset: AVAssetExportPresetLowQuality, xoaNguon: false).data, d.count <= gioiHan {
                    return (d, goc + ".mp4")
                }
                throw LoiMedia.quaLon
            }
            // nén lỗi khác -> dự phòng xuất theo preset
            for preset in [AVAssetExportPreset1280x720, AVAssetExportPreset640x480, AVAssetExportPresetLowQuality] {
                try Task.checkCancellation()
                if let d = try? await VideoHelper.chuyenSangMP4(from: nguon, preset: preset, xoaNguon: false).data, d.count <= gioiHan {
                    return (d, goc + ".mp4")
                }
            }
            // 3. không đổi được -> gửi tệp gốc (máy chủ có ffmpeg đổi tiếp), kiểm cỡ TRƯỚC khi đọc
            let thuocTinh = try? FileManager.default.attributesOfItem(atPath: nguon.path)
            let cop = (thuocTinh?[.size] as? NSNumber)?.intValue ?? 0
            if cop > gioiHan { throw LoiMedia.khongNen }
            guard let d = try? Data(contentsOf: nguon, options: .mappedIfSafe) else { throw LoiMedia.khongDoc }
            let ext = nguon.pathExtension.isEmpty ? "mov" : nguon.pathExtension.lowercased()
            return (d, goc + "." + ext)
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else { throw LoiMedia.khongDoc }
        if data.count > gioiHan { throw LoiMedia.anhQuaLon }
        // GIF: gửi nguyên (đổi JPG sẽ mất hoạt ảnh)
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .gif) }) { return (data, goc + ".gif") }
        if let jpg = ChuanTepGui.jpeg(tuDuLieu: data, boQuaNeuTrongSuot: true) { return (jpg, goc + ".jpg") }
        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "dat"
        return (data, goc + "." + ext)
    }
}
