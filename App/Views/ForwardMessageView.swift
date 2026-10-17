// Màn hình chọn người và nhóm để chuyển tiếp tin nhắn.
// Cho phép tìm kiếm, chọn một hoặc nhiều người/nhóm, nhập lời nhắn gửi kèm và gửi qua API /api/chuyen-tiep.

import SwiftUI

struct ForwardMessageView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let tin: Tin
    let cuocGocId: String

    @State private var dsCuoc: [Cuoc] = []
    @State private var tuKhoa = ""
    @State private var daChon = Set<String>()
    @State private var loiNhan = ""
    @State private var dangGui = false
    @State private var dangTaiDs = true
    @State private var thongBaoLoi: String?
    @State private var daGuiThanhCong = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Khung xem trước tin nhắn chuyển tiếp
                xemTruocTin

                // Danh sách hội thoại để chuyển tiếp
                if dangTaiDs {
                    Spacer()
                    ProgressView("Đang tải danh sách…")
                    Spacer()
                } else {
                    List {
                        ForEach(dsLoc) { c in
                            HStack(spacing: 12) {
                                AvatarView(ten: c.ten ?? c.id, anh: c.anh, khoa: c.id, kichThuoc: 44)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text((c.laNhomBool ? "👥 " : "") + (c.ten ?? c.id))
                                        .font(.system(size: 15, weight: .medium))
                                        .lineLimit(1)
                                    Text(c.laNhomBool ? "Nhóm" : "Trò chuyện cá nhân")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: daChon.contains(c.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(daChon.contains(c.id) ? ZaloMau.xanh : Color(.systemGray4))
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleChon(c.id)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $tuKhoa, prompt: "Tìm người hoặc nhóm…")
                }

                // Thanh nhập lời nhắn gửi kèm nếu đã chọn ít nhất 1 người
                if !daChon.isEmpty {
                    VStack(spacing: 6) {
                        Divider()
                        HStack(spacing: 10) {
                            TextField("Lời nhắn gửi kèm (không bắt buộc)…", text: $loiNhan)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 18))

                            Button {
                                Task { await thucHienChuyenTiep() }
                            } label: {
                                if dangGui {
                                    ProgressView()
                                        .frame(width: 32, height: 32)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white)
                                        .frame(width: 36, height: 36)
                                        .background(ZaloMau.xanh, in: Circle())
                                }
                            }
                            .disabled(dangGui)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .background(.bar)
                }
            }
            .navigationTitle("Chuyển tiếp tin nhắn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Huỷ") { dismiss() }
                        .disabled(dangGui)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !daChon.isEmpty {
                        Button {
                            Task { await thucHienChuyenTiep() }
                        } label: {
                            if dangGui {
                                ProgressView()
                            } else {
                                Text("Gửi (\(daChon.count))")
                                    .bold()
                            }
                        }
                        .disabled(dangGui)
                    }
                }
            }
            .task {
                await napDanhSachCuoc()
            }
            .alert("Lỗi chuyển tiếp", isPresented: Binding(get: { thongBaoLoi != nil }, set: { if !$0 { thongBaoLoi = nil } })) {
                Button("Đóng", role: .cancel) {}
            } message: {
                Text(thongBaoLoi ?? "")
            }
        }
    }

    @ViewBuilder
    private var xemTruocTin: some View {
        HStack(spacing: 10) {
            Image(systemName: iconKieuTin)
                .font(.system(size: 18))
                .foregroundStyle(ZaloMau.xanh)

            VStack(alignment: .leading, spacing: 2) {
                Text(tin.laToi ? "Tin nhắn của bạn" : (tin.tenNguoi ?? "Người gửi"))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(tomTatTin)
                    .font(.subheadline)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }

    private var iconKieuTin: String {
        switch tin.kieu {
        case "anh", "gif": return "photo"
        case "video": return "video"
        case "file": return "doc"
        case "sticker": return "face.smiling"
        case "ghiam": return "waveform"
        default: return "bubble.left"
        }
    }

    private var tomTatTin: String {
        if let c = tin.chu, !c.isEmpty { return c }
        if let f = tin.tenFile, !f.isEmpty { return f }
        switch tin.kieu {
        case "anh": return "[Hình ảnh]"
        case "gif": return "[GIF]"
        case "video": return "[Video]"
        case "sticker": return "[Sticker]"
        case "ghiam": return "[Tin nhắn thoại]"
        default: return "[Tin nhắn]"
        }
    }

    private var dsLoc: [Cuoc] {
        let q = tuKhoa.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return dsCuoc
        }
        return dsCuoc.filter { ($0.ten ?? $0.id).lowercased().contains(q) }
    }

    private func toggleChon(_ id: String) {
        if daChon.contains(id) {
            daChon.remove(id)
        } else {
            daChon.insert(id)
        }
    }

    private func napDanhSachCuoc() async {
        dangTaiDs = true
        defer { dangTaiDs = false }

        // Sử dụng cache có sẵn trước
        if !env.dsCuocCache.isEmpty {
            dsCuoc = Array(env.dsCuocCache.values).sorted { ($0.tinCuoiTs ?? 0) > ($1.tinCuoiTs ?? 0) }
        }

        // Tải danh sách mới nhất từ API
        do {
            let moi = try await env.api.dsCuoc()
            dsCuoc = moi
            for c in moi {
                env.dsCuocCache[c.id] = c
            }
        } catch {
            if dsCuoc.isEmpty {
                thongBaoLoi = "Không tải được danh sách trò chuyện: " + error.localizedDescription
            }
        }
    }

    private func thucHienChuyenTiep() async {
        guard !daChon.isEmpty else { return }
        dangGui = true
        defer { dangGui = false }

        let danhSachDich = Array(daChon)
        do {
            let kq = try await env.api.chuyenTiep(
                cuoc: cuocGocId,
                msg: tin.msgId,
                den: danhSachDich,
                loiNhan: loiNhan.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            if !kq.loi.isEmpty && kq.ok.isEmpty {
                let chiTiet = kq.loi.compactMap { $0.loi }.joined(separator: ", ")
                thongBaoLoi = "Không chuyển tiếp được: " + (chiTiet.isEmpty ? "Lỗi không xác định" : chiTiet)
                return
            }

            dismiss()
        } catch {
            thongBaoLoi = "Không thể chuyển tiếp: " + error.localizedDescription
        }
    }
}
