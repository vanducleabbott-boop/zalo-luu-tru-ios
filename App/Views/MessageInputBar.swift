// Ô soạn tin: nhiều dòng, nút gửi, nút ảnh (PhotosPicker) - khớp phần .soan trong web/index.html.

import SwiftUI
import PhotosUI

struct MessageInputBar: View {
    @ObservedObject var vm: ChatViewModel
    @FocusState.Binding var daFocus: Bool
    var onMoLichHen: (() -> Void)? = nil
    @State private var vanBan = ""
    @State private var dangGui = false
    @State private var anhDaChon: PhotosPickerItem?
    @State private var dangGuiAnh = false
    @State private var hienCamera = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Nút chụp ảnh trực tiếp bằng Camera
            Button {
                hienCamera = true
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(ZaloMau.xanh)
            }
            .disabled(dangGuiAnh)
            .sheet(isPresented: $hienCamera) {
                CameraPickerView { capturedImage in
                    Task {
                        await xuLyChupAnh(capturedImage)
                    }
                }
            }

            // Nút chọn ảnh / video từ Thư viện
            PhotosPicker(selection: $anhDaChon, matching: .any(of: [.images, .videos])) {
                if dangGuiAnh {
                    ProgressView()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 20))
                        .foregroundStyle(ZaloMau.xanh)
                }
            }
            .disabled(dangGuiAnh)
            .onChange(of: anhDaChon) { item in Task { await guiAnhDaChon(item) } }

            Button {
                onMoLichHen?()
            } label: {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 20))
                    .foregroundStyle(ZaloMau.xanh)
            }

            TextField(vm.cuoc.id == "so-tay" ? "Ghi chú…" : "Nhập tin nhắn…", text: $vanBan, axis: .vertical)
                .focused($daFocus)
                .lineLimit(1...5)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 18))

            Button { Task { await gui() } } label: {
                if dangGui { ProgressView() } else { Image(systemName: "paperplane.fill") }
            }
            .disabled(vanBan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || dangGui)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.bar)
    }

    private func gui() async {
        dangGui = true
        defer { dangGui = false }
        await vm.guiChu(vanBan)
        vanBan = ""
    }

    private func xuLyChupAnh(_ image: UIImage) async {
        dangGuiAnh = true
        defer { dangGuiAnh = false }
        guard let jpeg = image.jpegData(compressionQuality: 0.82) else { return }
        let ten = "chup_anh_\(Int(Date().timeIntervalSince1970)).jpg"
        await vm.guiFile(duLieu: jpeg, tenFile: ten)
    }

    private func guiAnhDaChon(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        dangGuiAnh = true
        defer { dangGuiAnh = false; anhDaChon = nil }

        // 1. Kiểm tra nếu là Video -> chuyển đổi chuẩn sang MP4 (H.264/AAC) để Zalo xem được trực tiếp
        let laVideo = item.supportedContentTypes.contains(where: {
            $0.conforms(to: .movie) || $0.conforms(to: .video) || $0.conforms(to: .quickTimeMovie) || $0.conforms(to: .mpeg4Movie)
        })

        if laVideo {
            if let movie = try? await item.loadTransferable(type: MovieFile.self) {
                if let (mp4Data, _) = try? await VideoHelper.chuyenSangMP4(from: movie.url) {
                    let ten = "video_\(Int(Date().timeIntervalSince1970)).mp4"
                    await vm.guiFile(duLieu: mp4Data, tenFile: ten)
                    return
                }
            }
        }

        // 2. Nếu là Ảnh hoặc tệp thông thường
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }

        if let img = UIImage(data: data), let jpeg = img.jpegData(compressionQuality: 0.85) {
            let ten = "anh_zalo_\(Int(Date().timeIntervalSince1970)).jpg"
            await vm.guiFile(duLieu: jpeg, tenFile: ten)
        } else {
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "dat"
            let ten = "tep_\(Int(Date().timeIntervalSince1970)).\(ext)"
            await vm.guiFile(duLieu: data, tenFile: ten)
        }
    }
}
