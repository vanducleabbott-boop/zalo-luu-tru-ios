import Foundation
import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers

struct MovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent("picked_\(UUID().uuidString).\(ext)")
            try? FileManager.default.removeItem(at: tempFile)
            try FileManager.default.copyItem(at: received.file, to: tempFile)
            return MovieFile(url: tempFile)
        }
    }
}

enum VideoHelper {
    /// Xuất/chuyển đổi bất kỳ video nào (MOV, QuickTime, HEVC, v.v.) sang MP4 (H.264 / AAC)
    /// tương thích 100% với Zalo để phát xem trực tiếp inline, không bị biến thành file tải về.
    static func chuyenSangMP4(from sourceURL: URL) async throws -> (data: Data, url: URL) {
        let asset = AVURLAsset(url: sourceURL)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("zalo_video_\(UUID().uuidString).mp4")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        // Ưu tiên preset 1280x720 hoặc MediumQuality cho video chat (nhẹ, nét, gửi siêu nhanh)
        let preset = AVAssetExportSession.exportPresets(compatibleWith: asset).contains(AVAssetExportPreset1280x720)
            ? AVAssetExportPreset1280x720
            : AVAssetExportPresetMediumQuality

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw NSError(domain: "VideoHelper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không thể khởi tạo xuất video MP4"])
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true // Fast start cho streaming

        await exportSession.export()

        if exportSession.status == .completed {
            let data = try Data(contentsOf: outputURL)
            // Dọn dẹp file nguồn tạm
            try? FileManager.default.removeItem(at: sourceURL)
            return (data, outputURL)
        } else {
            let loi = exportSession.error?.localizedDescription ?? "Lỗi xuất MP4"
            throw NSError(domain: "VideoHelper", code: -2, userInfo: [NSLocalizedDescriptionKey: loi])
        }
    }
}
