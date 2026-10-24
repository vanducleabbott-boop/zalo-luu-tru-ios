// Màn hình chọn người và nhóm để chuyển tiếp tin nhắn.
// Cho phép chuyển tiếp tới các đoạn chat lẻ HOẶC chọn nhóm phân loại để gửi hàng loạt.
// Hỗ trợ bớt người nhận: qua dải chip xoa nhanh, qua nút "Xem/Bớt" trong nhóm, hoặc bỏ chọn ở tab Đoạn chat.

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
    @State private var nhomDangXemThanhVien: NhomTuyChon?
    @State private var loiNhan = ""
    @State private var dangGui = false
    @State private var dangTaiDs = true
    @State private var thongBaoLoi: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Khung xem trước tin nhắn chuyển tiếp
                xemTruocTin

                // Tab chọn: Đoạn chat lẻ vs Nhóm phân loại
                Picker("Chế độ chọn", selection: $cheDoTab) {
                    Text("Đoạn chat (\(dsCuocDaChonCount))").tag(0)
                    Text("Nhóm phân loại (\(soNhomDangChon))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                // Dải chip hiển thị người nhận đã chọn - bấm x để bớt nhanh người nhận
                if !daChonCuoc.isEmpty {
                    daiChipNguoiNhan
                }

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
                if !daChonCuoc.isEmpty {
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
                    if !daChonCuoc.isEmpty {
                        Button {
                            Task { await thucHienChuyenTiep() }
                        } label: {
                            if dangGui {
                                ProgressView()
                            } else {
                                Text("Gửi (\(daChonCuoc.count))")
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
            .sheet(item: $nhomDangXemThanhVien) { nhom in
                ChiTietThanhVienForwardSheet(
                    nhom: nhom,
                    daChonCuoc: $daChonCuoc
                )
            }
            .alert("Lỗi chuyển tiếp", isPresented: Binding(get: { thongBaoLoi != nil }, set: { if !$0 { thongBaoLoi = nil } })) {
                Button("Đóng", role: .cancel) {}
            } message: {
                Text(thongBaoLoi ?? "")
            }
        }
    }

    private var dsCuocDaChonCount: Int {
        daChonCuoc.count
    }

    private var soNhomDangChon: Int {
        nhomManager.dsNhom.filter { nhom in
            !nhom.dsCuocId.isEmpty && nhom.dsCuocId.allSatisfy { daChonCuoc.contains($0) }
        }.count
    }

    // MARK: - Dải chip hiển thị người nhận đã chọn (cho phép bớt nhanh bằng nút x)
    private var daiChipNguoiNhan: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Người nhận (\(daChonCuoc.count)):")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Bỏ chọn hết") {
                    daChonCuoc.removeAll()
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(daChonCuoc), id: \.self) { cid in
                        let c = env.dsCuocCache[cid]
                        let ten = c?.ten ?? cid

                        HStack(spacing: 4) {
                            Text((c?.laNhomBool == true ? "👥 " : "") + ten)
                                .font(.caption)
                                .lineLimit(1)

                            Button {
                                daChonCuoc.remove(cid)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5), in: Capsule())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }
        }
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Danh sách đoạn chat lẻ
    private var danhSachDoanChat: some View {
        List {
            ForEach(dsLoc) { c in
                let daChon = daChonCuoc.contains(c.id)

                HStack(spacing: 12) {
                    AvatarView(ten: c.ten ?? c.id, anh: c.anh, khoa: c.id, kichThuoc: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text((c.laNhomBool ? "👥 " : "") + (c.ten ?? c.id))
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)
                        Text(c.laNhomBool ? "Nhóm Zalo" : "Trò chuyện cá nhân")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: daChon ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(daChon ? ZaloMau.xanh : Color(.systemGray4))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if daChon {
                        daChonCuoc.remove(c.id)
                    } else {
                        daChonCuoc.insert(c.id)
                    }
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
                        let soLuong = nhom.dsCuocId.count
                        let soDaChon = nhom.dsCuocId.filter { daChonCuoc.contains($0) }.count
                        let daChonHet = soLuong > 0 && soDaChon == soLuong
                        let daChonMotPhan = soDaChon > 0 && soDaChon < soLuong

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

                                HStack(spacing: 4) {
                                    if soLuong == 0 {
                                        Text("Chưa có đoạn chat")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("\(soDaChon)/\(soLuong) đã chọn")
                                            .font(.caption)
                                            .foregroundStyle(daChonMotPhan ? .orange : (daChonHet ? ZaloMau.xanh : .secondary))

                                        if daChonMotPhan {
                                            Text("• Đã bớt \(soLuong - soDaChon)")
                                                .font(.caption)
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                }
                            }

                            Spacer()

                            // Nút mở xem thành viên để thêm/bớt từng người trong nhóm này
                            if soLuong > 0 {
                                Button {
                                    nhomDangXemThanhVien = nhom
                                } label: {
                                    HStack(spacing: 2) {
                                        Text("Xem/Bớt")
                                            .font(.system(size: 12, weight: .semibold))
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundStyle(ZaloMau.xanh)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.blue.opacity(0.08), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }

                            // Nút tích chọn / bỏ chọn cả nhóm
                            Button {
                                toggleChonCaNhom(nhom)
                            } label: {
                                Image(systemName: daChonHet ? "checkmark.circle.fill" : (daChonMotPhan ? "minus.circle.fill" : "circle"))
                                    .font(.system(size: 24))
                                    .foregroundStyle(daChonHet ? ZaloMau.xanh : (daChonMotPhan ? .orange : Color(.systemGray4)))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
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
        return dsCuoc.filter { ($0.ten ?? $0.id).khopKhongDau(tuKhoa) }
    }

    private var dsNhomLoc: [NhomTuyChon] {
        return nhomManager.dsNhom.filter { $0.ten.khopKhongDau(tuKhoa) }
    }

    private func toggleChonCaNhom(_ nhom: NhomTuyChon) {
        let cacCuoc = nhom.dsCuocId
        guard !cacCuoc.isEmpty else { return }

        let daChonHet = cacCuoc.allSatisfy { daChonCuoc.contains($0) }
        if daChonHet {
            // Đang chọn hết -> bỏ chọn toàn bộ nhóm này
            for cid in cacCuoc {
                daChonCuoc.remove(cid)
            }
        } else {
            // Chưa chọn hết -> thêm toàn bộ nhóm này vào danh sách nhận
            for cid in cacCuoc {
                daChonCuoc.insert(cid)
            }
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
        let danhSachDich = Array(daChonCuoc)
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

/// Sheet xem danh sách thành viên trong nhóm để bớt/thêm từng người nhận
struct ChiTietThanhVienForwardSheet: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let nhom: NhomTuyChon
    @Binding var daChonCuoc: Set<String>

    private var dsCuocTrongNhom: [Cuoc] {
        nhom.dsCuocId.compactMap { env.dsCuocCache[$0] }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(dsCuocTrongNhom) { c in
                        let daChon = daChonCuoc.contains(c.id)

                        HStack(spacing: 12) {
                            AvatarView(ten: c.ten ?? c.id, anh: c.anh, khoa: c.id, kichThuoc: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text((c.laNhomBool ? "👥 " : "") + (c.ten ?? c.id))
                                    .font(.system(size: 15, weight: .medium))
                                    .lineLimit(1)
                                Text(c.laNhomBool ? "Nhóm Zalo" : "Trò chuyện cá nhân")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: daChon ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(daChon ? ZaloMau.xanh : Color(.systemGray4))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if daChon {
                                daChonCuoc.remove(c.id)
                            } else {
                                daChonCuoc.insert(c.id)
                            }
                        }
                    }
                } header: {
                    Text("Thành viên nhóm \"\(nhom.ten)\"")
                } footer: {
                    Text("Bỏ tích các đoạn chat bạn KHÔNG muốn gửi đến lần này.")
                }
            }
            .listStyle(.plain)
            .navigationTitle(nhom.ten)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chọn tất cả") {
                        for cid in nhom.dsCuocId {
                            daChonCuoc.insert(cid)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Xong") { dismiss() }
                        .bold()
                }
            }
        }
    }
}
