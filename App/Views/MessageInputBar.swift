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

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PhotosPicker(selection: $anhDaChon, matching: .any(of: [.images, .videos])) {
                Image(systemName: "photo.on.rectangle").font(.system(size: 20)).foregroundStyle(ZaloMau.xanh)
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

    private func guiAnhDaChon(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        dangGuiAnh = true
        defer { dangGuiAnh = false; anhDaChon = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let ten = item.supportedContentTypes.first?.preferredFilenameExtension.map { "anh_zalo.\($0)" } ?? "anh_zalo.jpg"
        await vm.guiFile(duLieu: data, tenFile: ten)
    }
}
