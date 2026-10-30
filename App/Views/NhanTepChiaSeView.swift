// v7.1: nhận tệp từ bảng Chia sẻ của iOS ("Mở bằng / Sao chép vào Zalo CF") - thay tiện ích ZaloShare,
// vì chứng chỉ Ad Hoc chỉ có 1 App ID nên iOS không cho tiện ích chạy (ID riêng: không cài được,
// ID chung với app: bấm vào không phản ứng). iOS mở app kèm URL tệp -> chọn người/nhóm -> gửi.

import SwiftUI

struct TepNhanDuoc: Identifiable {
    let id = UUID()
    let ten: String
    let duLieu: Data

    var laAnhVideo: Bool {
        ["jpg", "jpeg", "png", "heic", "gif", "webp", "mp4", "mov", "m4v"].contains((ten as NSString).pathExtension.lowercased())
    }

    /// Đọc tệp iOS đưa vào app (bản sao trong Inbox hoặc tệp gốc có quyền truy cập tạm).
    static func doc(_ url: URL) -> TepNhanDuoc? {
        guard url.isFileURL else { return nil }
        let coQuyen = url.startAccessingSecurityScopedResource()
        defer { if coQuyen { url.stopAccessingSecurityScopedResource() } }
        var duLieu: Data?
        var loi: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &loi) { u in
            duLieu = try? Data(contentsOf: u)
        }
        guard let duLieu, !duLieu.isEmpty else { return nil }
        // tệp trong Inbox của app là bản sao iOS tạo riêng -> đọc xong thì xoá cho đỡ chật máy
        if url.path.contains("/Documents/Inbox/") { try? FileManager.default.removeItem(at: url) }
        return TepNhanDuoc(ten: url.lastPathComponent, duLieu: duLieu)
    }
}

struct NhanTepChiaSeView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    private var dsTep: [TepNhanDuoc] { env.tepNhanDuoc }

    @State private var dsCuoc: [Cuoc] = []
    @State private var tuKhoa = ""
    @State private var daChon: [String] = []
    @State private var loiNhan = ""
    @State private var dangTai = true
    @State private var dangGui = false
    @State private var tienDo = ""
    @State private var loi: String?

    private var dsLoc: [Cuoc] { dsCuoc.filter { ($0.ten ?? $0.id).khopKhongDau(tuKhoa) } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(dsTep.prefix(3)) { t in
                        Label(t.ten, systemImage: t.laAnhVideo ? "photo" : "doc")
                            .font(.subheadline).lineLimit(1)
                    }
                    if dsTep.count > 3 {
                        Text("… và \(dsTep.count - 3) tệp khác").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground))

                if dangTai {
                    Spacer(); ProgressView("Đang tải danh sách…"); Spacer()
                } else {
                    List(dsLoc) { c in
                        let chon = daChon.contains(c.id)
                        HStack(spacing: 12) {
                            AvatarView(ten: c.ten ?? c.id, anh: c.anh, khoa: c.id, kichThuoc: 40)
                            Text((c.laNhomBool ? "👥 " : "") + (c.ten ?? c.id)).lineLimit(1)
                            Spacer()
                            Image(systemName: chon ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(chon ? ZaloMau.xanh : Color(.systemGray4))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let i = daChon.firstIndex(of: c.id) { daChon.remove(at: i) } else { daChon.append(c.id) }
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $tuKhoa, prompt: "Tìm người hoặc nhóm…")
                }

                if !daChon.isEmpty {
                    HStack {
                        TextField("Lời nhắn kèm (không bắt buộc)…", text: $loiNhan, axis: .vertical)
                            .lineLimit(1...3)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
                        if dangGui {
                            Text(tienDo).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(.bar)
                }
            }
            .navigationTitle("Gửi tệp tới…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Huỷ") { env.tepNhanDuoc = []; dismiss() }.disabled(dangGui)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await gui() }
                    } label: {
                        if dangGui { ProgressView() } else { Text("Gửi (\(daChon.count))").bold() }
                    }
                    .disabled(daChon.isEmpty || dangGui)
                }
            }
            .alert("Lỗi gửi tệp", isPresented: Binding(get: { loi != nil }, set: { if !$0 { loi = nil } })) {
                Button("Đóng", role: .cancel) {}
            } message: { Text(loi ?? "") }
            .task { await taiDs() }
        }
        .interactiveDismissDisabled(dangGui)
    }

    private func taiDs() async {
        // hiện ngay danh sách đã có trong bộ nhớ, rồi làm mới từ máy chủ
        dsCuoc = env.dsCuocCache.values.sorted { ($0.tinCuoiTs ?? 0) > ($1.tinCuoiTs ?? 0) }
        dangTai = dsCuoc.isEmpty
        defer { dangTai = false }
        if let ds = try? await env.api.dsCuoc() {
            dsCuoc = ds
            for c in ds { env.dsCuocCache[c.id] = c }
        } else if dsCuoc.isEmpty {
            loi = "Không tải được danh sách trò chuyện."
        }
    }

    private func gui() async {
        dangGui = true
        defer { dangGui = false }
        let chu = loiNhan.trimmingCharacters(in: .whitespacesAndNewlines)
        // nhiều ảnh/video -> 1 album như Zalo; còn lại gửi từng tệp
        let guiAlbum = dsTep.count > 1 && dsTep.allSatisfy(\.laAnhVideo)
        do {
            for (i, cuoc) in daChon.enumerated() {
                tienDo = "Gửi \(i + 1)/\(daChon.count)"
                if guiAlbum {
                    // mã tải lên tạm dùng cho 1 lần gửi album -> tải lên lại cho từng người nhận
                    var maAlbum: [String] = []
                    for t in dsTep { maAlbum.append(try await env.api.taiLenTam(duLieu: t.duLieu, tenFile: t.ten)) }
                    try await env.api.guiAlbum(cuoc: cuoc, ma: maAlbum)
                } else {
                    for t in dsTep { try await env.api.guiFile(cuoc: cuoc, duLieu: t.duLieu, tenFile: t.ten) }
                }
                if !chu.isEmpty { try await env.api.guiChu(cuoc: cuoc, chu: chu) }
            }
            env.tepNhanDuoc = []
            dismiss()
        } catch {
            loi = error.localizedDescription
        }
    }
}
