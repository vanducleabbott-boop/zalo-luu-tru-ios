// Ô soạn tin: nút dấu cộng (+) mở menu tính năng, ô nhập văn bản, nút gửi.

import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct MessageInputBar: View {
    @ObservedObject var vm: ChatViewModel
    @FocusState.Binding var daFocus: Bool
    var onMoLichHen: (() -> Void)? = nil

    @State private var vanBan = ""
    @State private var dangGui = false
    @State private var anhDaChon: [PhotosPickerItem] = []   // v4.3: chọn NHIỀU -> gửi 1 album như Zalo
    @State private var dangGuiMedia = false
    @State private var cheDoCameraDangMo: CameraCheDo? = nil
    @State private var hienThuVienAnh = false
    @State private var hienChonFile = false
    @State private var hienSticker = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Nút dấu cộng (+) duy nhất ở bên trái ô chat
            Menu {
                Button {
                    cheDoCameraDangMo = .photo
                } label: {
                    Label("Chụp ảnh", systemImage: "camera")
                }

                Button {
                    cheDoCameraDangMo = .video
                } label: {
                    Label("Quay video", systemImage: "video")
                }

                Button {
                    hienThuVienAnh = true
                } label: {
                    Label("Thư viện ảnh & video", systemImage: "photo.on.rectangle")
                }

                Button {
                    hienChonFile = true
                } label: {
                    Label("Gửi file / Tài liệu", systemImage: "doc")
                }

                Button {
                    onMoLichHen?()
                } label: {
                    Label("Đặt lịch hẹn", systemImage: "calendar.badge.clock")
                }
            } label: {
                if dangGuiMedia {
                    ProgressView()
                        .frame(width: 26, height: 26)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(ZaloMau.xanh)
                }
            }
            .disabled(dangGuiMedia)

            // Ô nhập văn bản
            TextField((vm.cuoc.id == "so-tay" || vm.cuoc.id == "so_tay") ? "Ghi chú…" : "Nhập tin nhắn…", text: $vanBan, axis: .vertical)
                .focused($daFocus)
                .lineLimit(1...5)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 18))

            // Nút sticker (như Zalo) - mở bảng chọn các bộ sticker đã tải sẵn
            Button { hienSticker = true } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 24))
                    .foregroundStyle(ZaloMau.xanh)
            }
            .accessibilityLabel("Sticker")

            // Nút gửi tin nhắn
            Button { Task { await gui() } } label: {
                if dangGui { ProgressView() } else { Image(systemName: "paperplane.fill") }
            }
            .disabled(vanBan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || dangGui)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.bar)
        // Máy ảnh / Máy quay trực tiếp
        .sheet(item: $cheDoCameraDangMo) { cheDo in
            CameraPickerView(cheDo: cheDo, onChupAnh: { capturedImage in
                Task {
                    await xuLyChupAnh(capturedImage)
                }
            }, onQuayVideo: { recordedVideoURL in
                Task {
                    await xuLyQuayVideo(recordedVideoURL)
                }
            })
        }
        .sheet(isPresented: $hienSticker) { StickerPickerView(vm: vm) }
        // Thư viện ảnh / video hệ thống
        .photosPicker(isPresented: $hienThuVienAnh, selection: $anhDaChon, maxSelectionCount: 30,
                      selectionBehavior: .ordered, matching: .any(of: [.images, .videos]))
        .onChange(of: anhDaChon) { ds in
            guard !ds.isEmpty else { return }
            Task { await guiCacAnhDaChon(ds) }
        }
        // Chọn file / tài liệu từ Files app
        .fileImporter(isPresented: $hienChonFile, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await xuLyGuiFileTuFiles(url) }
            case .failure(let error):
                print("Lỗi chọn file: \(error.localizedDescription)")
            }
        }
    }

    private func gui() async {
        dangGui = true
        defer { dangGui = false }
        await vm.guiChu(vanBan)
        vanBan = ""
    }

    private func xuLyChupAnh(_ image: UIImage) async {
        dangGuiMedia = true
        defer { dangGuiMedia = false }
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else { return }
        let ten = "chup_anh_\(Int(Date().timeIntervalSince1970)).jpg"
        await vm.guiFile(duLieu: jpeg, tenFile: ten)
    }

    private func xuLyQuayVideo(_ sourceURL: URL) async {
        dangGuiMedia = true
        defer { dangGuiMedia = false }
        do {
            let (mp4Data, _) = try await VideoHelper.chuyenSangMP4(from: sourceURL)
            let ten = "video_quay_\(Int(Date().timeIntervalSince1970)).mp4"
            await vm.guiFile(duLieu: mp4Data, tenFile: ten)
        } catch {
            if let data = try? Data(contentsOf: sourceURL) {
                let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
                let ten = "video_quay_\(Int(Date().timeIntervalSince1970)).\(ext)"
                await vm.guiFile(duLieu: data, tenFile: ten)
            }
        }
    }

    private func xuLyGuiFileTuFiles(_ url: URL) async {
        dangGuiMedia = true
        defer { dangGuiMedia = false }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let tenFile = url.lastPathComponent
            let duoi = url.pathExtension.lowercased()

            // Nếu người dùng chọn file video từ tệp -> tự động chuyển MP4 để Zalo xem inline được
            let laVideo = ["mov", "mp4", "m4v", "3gp", "avi", "webm", "mkv"].contains(duoi)
            if laVideo {
                if let (mp4Data, _) = try? await VideoHelper.chuyenSangMP4(from: url) {
                    let tenMP4 = (tenFile as NSString).deletingPathExtension + ".mp4"
                    await vm.guiFile(duLieu: mp4Data, tenFile: tenMP4)
                    return
                }
            }

            let duLieu = try Data(contentsOf: url)
            await vm.guiFile(duLieu: duLieu, tenFile: tenFile)
        } catch {
            print("Không thể đọc file: \(error)")
        }
    }

    /// v4.3: nhiều ảnh/video chọn 1 lần -> 1 album (như Zalo gốc); chọn 1 thì gửi thường.
    private func guiCacAnhDaChon(_ ds: [PhotosPickerItem]) async {
        dangGuiMedia = true
        defer { dangGuiMedia = false; anhDaChon = [] }
        var tep: [(duLieu: Data, tenFile: String)] = []
        for (i, item) in ds.enumerated() {
            if let t = await chuanBiTep(item, thuTu: i) { tep.append(t) }
        }
        await vm.guiAlbum(tep)
    }

    private func chuanBiTep(_ item: PhotosPickerItem, thuTu: Int) async -> (duLieu: Data, tenFile: String)? {
        let dau = "\(Int(Date().timeIntervalSince1970))_\(thuTu + 1)"
        // 1. Video -> chuyển chuẩn MP4 (H.264/AAC) để Zalo xem được trực tiếp
        let laVideo = item.supportedContentTypes.contains(where: {
            $0.conforms(to: .movie) || $0.conforms(to: .video) || $0.conforms(to: .quickTimeMovie) || $0.conforms(to: .mpeg4Movie)
        })
        if laVideo, let movie = try? await item.loadTransferable(type: MovieFile.self),
           let (mp4Data, _) = try? await VideoHelper.chuyenSangMP4(from: movie.url) {
            return (mp4Data, "video_\(dau).mp4")
        }
        // 2. Ảnh hoặc tệp thông thường
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        if let img = UIImage(data: data), let jpeg = img.jpegData(compressionQuality: 0.85) {
            return (jpeg, "anh_zalo_\(dau).jpg")
        }
        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "dat"
        return (data, "tep_\(dau).\(ext)")
    }
}
