// Màn hình Tab "Nhóm": Quản lý danh sách các Group phân loại (Đặt hàng, Nhóm, Gia đình...).
// Mỗi Group chứa nhiều đoạn chat nhỏ bên trong.

import SwiftUI

struct GroupListView: View {
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject private var manager = NhomChatManager.shared

    @State private var hienDialogTaoNhom = false
    @State private var tenNhomMoi = ""
    @State private var nhomCanDoiTen: NhomTuyChon?
    @State private var tenMoi = ""

    var body: some View {
        NavigationStack {
            Group {
                if manager.dsNhom.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Chưa có nhóm phân loại nào")
                            .font(.headline)
                        Text("Bạn có thể tạo nhóm (ví dụ: Đặt hàng, Khách VIP) để gom các đoạn chat nhỏ vào một nơi.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button {
                            hienDialogTaoNhom = true
                        } label: {
                            Text("Tạo nhóm đầu tiên")
                                .bold()
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(ZaloMau.xanh, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(manager.dsNhom) { nhom in
                            NavigationLink {
                                GroupDetailView(nhomId: nhom.id)
                            } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.blue.opacity(0.12))
                                            .frame(width: 48, height: 48)
                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 22))
                                            .foregroundStyle(ZaloMau.xanh)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(nhom.ten)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(.primary)

                                        Text(moTaSoLuong(nhom))
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    manager.xoaNhom(id: nhom.id)
                                } label: {
                                    Label("Xoá", systemImage: "trash")
                                }

                                Button {
                                    nhomCanDoiTen = nhom
                                    tenMoi = nhom.ten
                                } label: {
                                    Label("Đổi tên", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Nhóm")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        tenNhomMoi = ""
                        hienDialogTaoNhom = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Tạo nhóm mới", isPresented: $hienDialogTaoNhom) {
                TextField("Tên nhóm (ví dụ: Đặt hàng, Khách VIP)", text: $tenNhomMoi)
                Button("Tạo") {
                    let ten = tenNhomMoi.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !ten.isEmpty {
                        manager.taoNhom(ten: ten)
                    }
                }
                Button("Huỷ", role: .cancel) {}
            } message: {
                Text("Nhập tên nhóm phân loại để quản lý các đoạn chat.")
            }
            .alert("Đổi tên nhóm", isPresented: Binding(
                get: { nhomCanDoiTen != nil },
                set: { if !$0 { nhomCanDoiTen = nil } }
            )) {
                TextField("Tên mới", text: $tenMoi)
                Button("Lưu") {
                    if let nhom = nhomCanDoiTen {
                        manager.doiTenNhom(id: nhom.id, tenMoi: tenMoi)
                    }
                }
                Button("Huỷ", role: .cancel) {}
            }
            .refreshable {
                await manager.dongBoVoiServer(api: env.api)
            }
            .task {
                await manager.dongBoVoiServer(api: env.api)
            }
        }
    }

    private func moTaSoLuong(_ nhom: NhomTuyChon) -> String {
        let n = nhom.dsCuocId.count
        if n == 0 { return "Chưa có đoạn chat nào" }
        return "\(n) đoạn chat"
    }
}

/// Chi tiết của một Group: hiển thị toàn bộ các đoạn chat con bên trong group đó
struct GroupDetailView: View {
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject private var manager = NhomChatManager.shared

    let nhomId: String

    @State private var hienSheetThemChat = false

    private var nhomHienTai: NhomTuyChon? {
        manager.dsNhom.first(where: { $0.id == nhomId })
    }

    private var dsCuocTrongNhom: [Cuoc] {
        guard let nhom = nhomHienTai else { return [] }
        return nhom.dsCuocId.compactMap { env.dsCuocCache[$0] }
    }

    var body: some View {
        Group {
            if dsCuocTrongNhom.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("Nhóm này chưa có đoạn chat nào")
                        .font(.headline)
                    Text("Bạn có thể thêm các đoạn chat vào nhóm này hoặc ấn giữ vào đoạn chat ở tab Tin nhắn để gán nhóm.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button {
                        hienSheetThemChat = true
                    } label: {
                        Label("Thêm đoạn chat", systemImage: "plus.circle.fill")
                            .bold()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(ZaloMau.xanh, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(dsCuocTrongNhom) { c in
                        NavigationLink {
                            ChatView(cuoc: c)
                        } label: {
                            ConversationRow(c: c)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                manager.xoaCuocKhoiNhom(nhomId: nhomId, cuocId: c.id)
                            } label: {
                                Label("Bỏ khỏi nhóm", systemImage: "folder.badge.minus")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(nhomHienTai?.ten ?? "Chi tiết nhóm")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    hienSheetThemChat = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
        .sheet(isPresented: $hienSheetThemChat) {
            ThemChatVaoNhomSheet(nhomId: nhomId)
        }
    }
}

/// Sheet chọn nhiều đoạn chat để thêm vào nhóm hiện tại
struct ThemChatVaoNhomSheet: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = NhomChatManager.shared

    let nhomId: String

    @State private var tuKhoa = ""
    @State private var daChon: Set<String> = []

    private var nhomHienTai: NhomTuyChon? {
        manager.dsNhom.first(where: { $0.id == nhomId })
    }

    private var tatCaCuoc: [Cuoc] {
        Array(env.dsCuocCache.values).sorted { ($0.tinCuoiTs ?? 0) > ($1.tinCuoiTs ?? 0) }
    }

    private var dsLoc: [Cuoc] {
        let q = tuKhoa.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return tatCaCuoc }
        return tatCaCuoc.filter { ($0.ten ?? $0.id).lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
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
                        if daChon.contains(c.id) {
                            daChon.remove(c.id)
                        } else {
                            daChon.insert(c.id)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $tuKhoa, prompt: "Tìm người hoặc nhóm…")
            .navigationTitle("Chọn đoạn chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Lưu (\(daChon.count))") {
                        luu()
                    }
                    .bold()
                }
            }
            .onAppear {
                if let nhom = nhomHienTai {
                    daChon = Set(nhom.dsCuocId)
                }
            }
        }
    }

    private func luu() {
        guard let idx = manager.dsNhom.firstIndex(where: { $0.id == nhomId }) else {
            dismiss()
            return
        }
        manager.dsNhom[idx].dsCuocId = Array(daChon)
        manager.luuDanhSach()
        dismiss()
    }
}
