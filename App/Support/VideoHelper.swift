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
    /// v8.3: `preset` (mặc định 720p) để xuất lại nhỏ hơn khi video quá lớn; `xoaNguon: false` giữ tệp nguồn để xuất lại.
    /// Tệp MP4 tạm tự xoá khi hàm kết thúc (kể cả lỗi) -> `url` trả về chỉ để tương thích, KHÔNG dùng (đã bị xoá), hãy dùng `data`.
    static func chuyenSangMP4(from sourceURL: URL, preset: String? = nil, xoaNguon: Bool = true) async throws -> (data: Data, url: URL) {
        let asset = AVURLAsset(url: sourceURL)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("zalo_video_\(UUID().uuidString).mp4")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        defer { try? FileManager.default.removeItem(at: outputURL) }   // v8.3: không rò tệp tạm khi lỗi

        // Ưu tiên preset 1280x720 hoặc MediumQuality cho video chat (nhẹ, nét, gửi siêu nhanh)
        let hopLe = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let tenPreset: String
        if let preset {
            // v8.4: preset được chỉ định mà không hợp lệ -> báo lỗi để nơi gọi thử bước khác (không lặng lẽ rơi về 720p)
            guard hopLe.contains(preset) else {
                throw NSError(domain: "VideoHelper", code: -3, userInfo: [NSLocalizedDescriptionKey: "Preset không hỗ trợ: \(preset)"])
            }
            tenPreset = preset
        } else if hopLe.contains(AVAssetExportPreset1280x720) {
            tenPreset = AVAssetExportPreset1280x720
        } else {
            tenPreset = AVAssetExportPresetMediumQuality
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: tenPreset) else {
            throw NSError(domain: "VideoHelper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không thể khởi tạo xuất video MP4"])
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true // Fast start cho streaming

        await exportSession.export()

        if exportSession.status == .completed {
            let data = try Data(contentsOf: outputURL)
            // Dọn dẹp file nguồn tạm
            if xoaNguon { try? FileManager.default.removeItem(at: sourceURL) }
            return (data, outputURL)
        } else {
            let loi = exportSession.error?.localizedDescription ?? "Lỗi xuất MP4"
            throw NSError(domain: "VideoHelper", code: -2, userInfo: [NSLocalizedDescriptionKey: loi])
        }
    }

    /// Mã lỗi NSError (domain "VideoHelper") khi video quá dài, không nén nổi xuống dưới giới hạn.
    static let maLoiQuaDai = -10

    /// v8.4: nén video theo đúng dung lượng (AVAssetReader + AVAssetWriter): H.264, cạnh dài <= 1280 (giảm theo bitrate), <= 30fps,
    /// bitrate tính theo thời lượng để chắc chắn dưới `gioiHanByte`. HEVC/HDR/4K60 đều thành MP4 H.264 SDR (tone-map qua video composition),
    /// đã xoay đúng chiều. Không xoá tệp nguồn.
    static func nenTheoDungLuong(from src: URL, gioiHanByte: Int = 90_000_000) async throws -> Data {
        func loi(_ ma: Int, _ noiDung: String) -> NSError {
            NSError(domain: "VideoHelper", code: ma, userInfo: [NSLocalizedDescriptionKey: noiDung])
        }
        let asset = AVURLAsset(url: src)
        let thoiLuong = try await asset.load(.duration)
        let giay = CMTimeGetSeconds(thoiLuong)
        guard giay.isFinite, giay > 0 else { throw loi(-11, "Không đọc được thời lượng video") }

        let aTrack = try await asset.loadTracks(withMediaType: .audio).first
        let bitrate = min(2_000_000, Int(Double(gioiHanByte) * 8 * 0.92 / giay) - (aTrack != nil ? 128_000 : 0))
        if bitrate < 150_000 { throw loi(maLoiQuaDai, "Video quá dài, không nén được xuống dưới giới hạn") }
        let canhMax: CGFloat
        if bitrate >= 1_500_000 { canhMax = 1280 }
        else if bitrate >= 800_000 { canhMax = 960 }
        else if bitrate >= 450_000 { canhMax = 720 }
        else { canhMax = 480 }

        let dsVideo = try await asset.loadTracks(withMediaType: .video)
        guard let vTrack = dsVideo.first else { throw loi(-12, "Tệp không có hình ảnh") }
        let kichThuoc = try await vTrack.load(.naturalSize)
        let xoay = try await vTrack.load(.preferredTransform)
        let fpsGoc = try await vTrack.load(.nominalFrameRate)

        // kích thước ĐÃ XOAY (iPhone quay dọc: naturalSize ngang + transform xoay 90 độ)
        let daXoay = CGRect(origin: .zero, size: kichThuoc).applying(xoay)
        let rongXoay = abs(daXoay.width)
        let caoXoay = abs(daXoay.height)
        let canhDai = max(rongXoay, caoXoay)
        guard canhDai > 0 else { throw loi(-13, "Kích thước video không hợp lệ") }
        let tiLe = min(1.0, canhMax / canhDai)
        func chan(_ x: CGFloat) -> Int { max(2, Int((x * tiLe / 2).rounded()) * 2) }
        let rong = chan(rongXoay)
        let cao = chan(caoXoay)

        // video composition: tone-map HDR -> SDR BT.709, xoay, thu nhỏ, giảm fps
        let vc = AVMutableVideoComposition()
        vc.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        vc.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        vc.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        let fps: Double = (fpsGoc > 0 && fpsGoc < 30) ? Double(fpsGoc) : 30
        vc.frameDuration = fps == 30 ? CMTime(value: 1, timescale: 30) : CMTime(seconds: 1.0 / fps, preferredTimescale: 600)
        vc.renderSize = CGSize(width: rong, height: cao)
        let lenh = AVMutableVideoCompositionInstruction()
        lenh.timeRange = CMTimeRange(start: .zero, duration: thoiLuong)
        let lop = AVMutableVideoCompositionLayerInstruction(assetTrack: vTrack)
        lop.setTransform(xoay.concatenating(CGAffineTransform(scaleX: tiLe, y: tiLe)), at: .zero)
        lenh.layerInstructions = [lop]
        vc.instructions = [lenh]

        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("zalo_nen_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outURL)
        defer { try? FileManager.default.removeItem(at: outURL) }

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        let vOut = AVAssetReaderVideoCompositionOutput(videoTracks: [vTrack], videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        ])
        vOut.videoComposition = vc
        vOut.alwaysCopiesSampleData = false
        guard reader.canAdd(vOut) else { throw loi(-14, "Không đọc được luồng video") }
        reader.add(vOut)

        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: rong,
            AVVideoHeightKey: cao,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoExpectedSourceFrameRateKey: Int(fps.rounded())
            ] as [String: Any]
        ])
        vIn.expectsMediaDataInRealTime = false
        vIn.transform = .identity   // đã xoay trong video composition
        guard writer.canAdd(vIn) else { throw loi(-15, "Không ghi được luồng video") }
        writer.add(vIn)

        var aOut: AVAssetReaderTrackOutput?
        var aIn: AVAssetWriterInput?
        if let aTrack {
            let o = AVAssetReaderTrackOutput(track: aTrack, outputSettings: [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ])
            o.alwaysCopiesSampleData = false
            let i = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000
            ])
            i.expectsMediaDataInRealTime = false
            if reader.canAdd(o), writer.canAdd(i) {
                reader.add(o)
                writer.add(i)
                aOut = o
                aIn = i
            }
        }

        guard writer.startWriting() else { throw writer.error ?? loi(-16, "Không bắt đầu ghi được") }
        guard reader.startReading() else {
            writer.cancelWriting()
            throw reader.error ?? loi(-17, "Không bắt đầu đọc được")
        }
        writer.startSession(atSourceTime: .zero)

        let nhom = DispatchGroup()

        // bơm mẫu từ reader sang writer cho 1 input; kết thúc đúng 1 lần (leave 1 lần)
        func bom(_ input: AVAssetWriterInput, ten: String, _ layMau: @escaping () -> CMSampleBuffer?) {
            nhom.enter()
            var xong = false
            input.requestMediaDataWhenReady(on: DispatchQueue(label: ten, qos: .userInitiated)) {
                func ketThuc() {
                    if xong { return }
                    xong = true
                    if writer.status == .writing { input.markAsFinished() }
                    nhom.leave()
                }
                if xong { return }
                while input.isReadyForMoreMediaData {
                    guard writer.status == .writing, reader.status == .reading,
                          let sb = layMau(), input.append(sb) else {
                        ketThuc()
                        return
                    }
                }
            }
        }

        bom(vIn, ten: "zalo.nen.video") { vOut.copyNextSampleBuffer() }
        if let aOut, let aIn {
            bom(aIn, ten: "zalo.nen.audio") { aOut.copyNextSampleBuffer() }
        }

        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                nhom.notify(queue: DispatchQueue.global()) { cont.resume() }
            }
        } onCancel: {
            reader.cancelReading()
        }

        if Task.isCancelled {
            reader.cancelReading()
            writer.cancelWriting()
            throw CancellationError()
        }
        if reader.status != .completed {
            let e = reader.error
            reader.cancelReading()
            writer.cancelWriting()
            throw e ?? loi(-18, "Lỗi đọc video")
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? loi(-19, "Lỗi ghi video") }
        return try Data(contentsOf: outURL, options: .mappedIfSafe)
    }
}
