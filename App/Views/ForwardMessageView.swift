// Màn hình chọn người và nhóm để chuyển tiếp tin nhắn.
// Cho phép chuyển tiếp tới các đoạn chat lẻ HOẶC chọn nhóm phân loại để gửi hàng loạt tới mọi đoạn chat trong nhóm.

import SwiftUI

struct ForwardMessageView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var nhomManager = NhomChatManager.shared

    let tin: Tin
    let cuocGocId: String

    @State private var dsCuoc: [Cuoc] = []
    @State private var tuKhoa = ""
    @State private var cheDoTab = 0 // 0: Đoạn chat, 1: Nhóm phân loại
    @State private var daChonCuoc = Set<String>()
    @State private var daChonNhom = Set<String>()
    @State private var loiNhan = ""
    @State private var dangGui = false
    @State private var dangTaiDs = true
    @State private var thongBaoLoi: String?

    /// Tập hợp các ID cuộc trò chuyện duy nhất sẽ nhận tin nhắn
    private var dsCuocNhanTin: [String] {
        var tapHop = daChonCuoc
        for nhomId in daChonNhom {
            if let nhom = nhomManager.dsNhom.first(where: { $0.id == nhomId }) {
                for cid in nhom.dsCuocId {
                    tapHop.insert(cid)
                }
            }
        }
        return Array(tapHop)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Khung xem trước tin nhắn chuyển tiếp
                xemTruocTin

                // Tab chọn: Đoạn chat lẻ vs Nhóm phân loại
                Picker("Chế độ chọn", selection: $cheDoTab) {
                    Text("Đoạn chat (\(dsCuocNhanLeCount))").tag(0)
                    Text("Nhóm phân loại (\(daChonNhom.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                Divider()

                // Danh sách hội thoại hoặc nhóm để chuyển tiếp
                if dangTaiDs {
                    Spacer()
                    ProgressView("Đang tải danh sách…")
                    Spacer()
                } else {
                    if cheDoTab == 0 {
                        danhSachDoanChat
                    } else {
                        danhSachNhom
                    }
                }

                // Thanh nhập lời nhắn gửi kèm nếu đã chọn ít nhất 1 người
                if !dsCuocNhanTin.isEmpty {
                    thanhGuiLoiNhan
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
                    if !dsCuocNhanTin.isEmpty {
                        Button {
                            Task { await thucHienChuyenTiep() }
                        } label: {
                            if dangGui {
                                ProgressView()
                            } else {
                                Text("Gửi (\(dsCuocNhanTin.count))")
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

    private var dsCuocNhanLeCount: Int {
        daChonCuoc.count
    }

    // MARK: - Danh sách đoạn chat lẻ
    private var danhSachDoanChat: some View {
        List {
            ForEach(dsLoc) { c in
                let daChonTrucTiep = daChonCuoc.contains(c.id)
                let daChonQuaNhom = !daChonTrucTiep && daChonNhom.contains { nid in
                    nhomManager.dsNhom.first(where: { $0.id == nid })?.dsCuocId.contains(c.id) == true
                }

                HStack(spacing: 12) {
                    AvatarView(ten: c.ten ?? c.id, anh: c.anh, khoa: c.id, kichThuoc: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text((c.laNhomBool ? "👥 " : "") + (c.ten ?? c.id))
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(c.laNhomBool ? "Nhóm Zalo" : "Cá nhân")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if daChonQuaNhom {
                                Text("• Đã chọn qua Nhóm")
                                    .font(.caption)
                                    .foregroundStyle(ZaloMau.xanh)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: (daChonTrucTiep || daChonQuaNhom) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle((daChonTrucTiep || daChonQuaNhom) ? ZaloMau.xanh : Color(.systemGray4))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleChonCuoc(c.id)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $tuKhoa, prompt: "Tìm người hoặc nhóm…")
    }

    // MARK: - Danh sách Nhóm phân loại
    private var danhSachNhom: some View {
        Group {
            if dsNhomLoc.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text(nhomManager.dsNhom.isEmpty ? "Chưa có nhóm phân loại nào" : "Không tìm thấy nhóm")
                        .font(.headline)
                    Text(nhomManager.dsNhom.isEmpty ? "Hãy vào tab 'Nhóm' trên màn hình chính để tạo nhóm (ví dụ: Đặt hàng, Khách VIP) và gom các đoạn chat vào." : "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(dsNhomLoc) { nhom in
                        let daChon = daChonNhom.contains(nhom.id)

                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.blue.opacity(0.12))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(ZaloMau.xanh)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(nhom.ten)
                                    .font(.system(size: 15, weight: .semibold))
                                    .lineLimit(1)
                                Text(tenCacCuocTrongNhom(nhom))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: daChon ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(daChon ? ZaloMau.xanh : Color(.systemGray4))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleChonNhom(nhom.id)
                        }
                    }
                }
                .listStyle(.plain)
                .searchable(text: $tuKhoa, prompt: "Tìm nhóm phân loại…")
            }
        }
    }

    private var thanhGuiLoiNhan: some View {
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
        if q.isEmpty { return dsCuoc }
        return dsCuoc.filter { ($0.ten ?? $0.id).lowercased().contains(q) }
    }

    private var dsNhomLoc: [NhomTuyChon] {
        let q = tuKhoa.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return nhomManager.dsNhom }
        return nhomManager.dsNhom.filter { $0.ten.lowercased().contains(q) }
    }

    private func tenCacCuocTrongNhom(_ nhom: NhomTuyChon) -> String {
        let ten = nhom.dsCuocId.compactMap { cid -> String? in
            guard let c = env.dsCuocCache[cid] else { return nil }
            return c.ten ?? c.id
        }
        if ten.isEmpty { return "Chưa có đoạn chat nào" }
        let hienThi = ten.prefix(3).joined(separator: ", ")
        if ten.count > 3 {
            return "\(ten.count) đoạn chat: \(hienThi), …"
        }
        return "\(ten.count) đoạn chat: \(hienThi)"
    }

    private func toggleChonCuoc(_ id: String) {
        if daChonCuoc.contains(id) {
            daChonCuoc.remove(id)
        } else {
            daChonCuoc.insert(id)
        }
    }

    private func toggleChonNhom(_ nhomId: String) {
        if daChonNhom.contains(nhomId) {
            daChonNhom.remove(nhomId)
        } else {
            daChonNhom.insert(nhomId)
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
        let danhSachDich = dsCuocNhanTin
        guard !danhSachDich.isEmpty else { return }
        dangGui = true
        defer { dangGui = false }

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
