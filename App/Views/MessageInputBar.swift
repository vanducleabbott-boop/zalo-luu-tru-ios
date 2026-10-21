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
    @State private var tagDaChon: [TagChon] = []
    @State private var daDongTagTamThoi = false
    @State private var doDaiVanBanTruoc: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Danh sách gợi ý tag thành viên khi gõ @ trong nhóm (v4.9)
            if hienGoiYTag, !danhSachGoiYTag.isEmpty {
                bangGoiYTag
            }

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

                // Nút @ tag nhanh trong nhóm (v4.9)
                if vm.cuoc.laNhomBool {
                    Button {
                        daDongTagTamThoi = false
                        if !vanBan.isEmpty && !vanBan.hasSuffix(" ") && !vanBan.hasSuffix("\n") {
                            vanBan += " @"
                        } else {
                            vanBan += "@"
                        }
                        daFocus = true
                        Task { await vm.taiThanhVienNhom() }
                    } label: {
                        Image(systemName: "at")
                            .font(.system(size: 22))
                            .foregroundStyle(ZaloMau.xanh)
                    }
                    .accessibilityLabel("Tag thành viên")
                }

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
        }
        .background(.bar)
        .onChange(of: vanBan) { moi in
            if moi.count != doDaiVanBanTruoc {
                if moi.hasSuffix("@") || !moi.contains("@") {
                    daDongTagTamThoi = false
                }
                doDaiVanBanTruoc = moi.count
            }
            if hienGoiYTag && vm.thanhVienNhom.isEmpty {
                Task { await vm.taiThanhVienNhom() }
            }
        }
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

    // ---------------------------------------------------------------- Gợi ý tag thành viên (@)
    private var thongTinTagDangGo: (viTriAt: String.Index, query: String)? {
        guard vm.cuoc.laNhomBool, !daDongTagTamThoi else { return nil }
        guard let atRange = vanBan.range(of: "@", options: .backwards) else { return nil }
        if atRange.lowerBound > vanBan.startIndex {
            let truocAt = vanBan[vanBan.index(before: atRange.lowerBound)]
            guard truocAt.isWhitespace || truocAt.isNewline else { return nil }
        }
        let sauAt = vanBan[atRange.upperBound...]
        if sauAt.contains("\n") || sauAt.count > 30 { return nil }
        return (atRange.lowerBound, String(sauAt))
    }

    private var hienGoiYTag: Bool {
        thongTinTagDangGo != nil
    }

    private var danhSachGoiYTag: [ThanhVien] {
        guard let info = thongTinTagDangGo else { return [] }
        let q = info.query.boDau.trimmingCharacters(in: .whitespaces)
        let tuKhoa = q.split(separator: " ").map(String.init)

        let tagAll = ThanhVien(uid: "-1", ten: "All", anh: nil)
        let coAll: Bool = q.isEmpty || "all tat ca moi nguoi".contains(q) || "all".hasPrefix(q)

        let ds = vm.thanhVienNhom
        let loc: [ThanhVien]
        if tuKhoa.isEmpty {
            loc = ds
        } else {
            loc = ds.filter { m in
                let tenBoDau = m.ten.boDau
                return tuKhoa.allSatisfy { w in tenBoDau.contains(w) }
            }.sorted { a, b in
                let cacTuA = a.ten.boDau.split(separator: " ")
                let cacTuB = b.ten.boDau.split(separator: " ")
                let diemA = tuKhoa.allSatisfy { w in cacTuA.contains { $0.hasPrefix(w) } } ? 0 : 1
                let diemB = tuKhoa.allSatisfy { w in cacTuB.contains { $0.hasPrefix(w) } } ? 0 : 1
                if diemA != diemB { return diemA < diemB }
                return a.ten.localizedCompare(b.ten) == .orderedAscending
            }
        }

        var ketQua: [ThanhVien] = []
        if coAll {
            ketQua.append(tagAll)
        }
        ketQua.append(contentsOf: loc.prefix(30))
        return ketQua
    }

    private func chonTag(_ m: ThanhVien) {
        guard let info = thongTinTagDangGo else { return }
        let chen = "@\(m.ten) "
        vanBan.replaceSubrange(info.viTriAt..<vanBan.endIndex, with: chen)
        tagDaChon.append(TagChon(uid: m.uid, ten: m.ten))
        daDongTagTamThoi = true
        doDaiVanBanTruoc = vanBan.count
    }

    private var bangGoiYTag: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "at")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(ZaloMau.xanh)
                Text("Nhắc đến thành viên")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    daDongTagTamThoi = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(.systemGray6))

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(danhSachGoiYTag, id: \.uid) { item in
                        Button {
                            chonTag(item)
                        } label: {
                            HStack(spacing: 12) {
                                if item.uid == "-1" {
                                    ZStack {
                                        Circle().fill(ZaloMau.xanh).frame(width: 36, height: 36)
                                        Image(systemName: "person.2.fill")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("@All")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.primary)
                                        Text("Báo cho cả nhóm")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    AvatarView(ten: item.ten, anh: item.anh, khoa: item.uid, kichThuoc: 36)
                                    Text(item.ten)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 62)
                    }
                }
            }
            .frame(maxHeight: 220)
            .background(Color(.systemBackground))

            Divider()
        }
        .background(Color(.systemBackground))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func gui() async {
        dangGui = true
        defer { dangGui = false }
        let tags = vm.cuoc.laNhomBool ? DinhDangChu.tinhTag(chu: vanBan, daChon: tagDaChon) : []
        await vm.guiChu(vanBan, tag: tags)
        vanBan = ""
        tagDaChon = []
        daDongTagTamThoi = false
        doDaiVanBanTruoc = 0
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
