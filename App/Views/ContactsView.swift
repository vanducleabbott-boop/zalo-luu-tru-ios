// LƯU Ý: web_zalo.mjs không có route GET liệt kê danh bạ riêng - /api/danh-ba chỉ là POST để nạp
// bạn bè/nhóm Zalo vào cơ sở dữ liệu hội thoại (kho.dsCuoc), không trả danh sách có cấu trúc.
// Nên màn này dùng lại /api/cuoc (như tab Tin nhắn) nhưng sắp theo tên A-Z, có nút "Làm mới danh bạ".

import SwiftUI

struct ContactsView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var ds: [Cuoc] = []
    @State private var dangTai = false
    @State private var dangLamMoi = false
    @State private var thongBao: String?

    private var dsSapXep: [Cuoc] {
        ds.filter { $0.id != "so-tay" }.sorted { ($0.ten ?? $0.id).localizedStandardCompare($1.ten ?? $1.id) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if let thongBao { Section { Text(thongBao).font(.footnote).foregroundStyle(.secondary) } }
                ForEach(dsSapXep) { c in
                    NavigationLink(value: c) {
                        HStack(spacing: 12) {
                            AvatarView(ten: c.ten ?? c.id, anh: c.anh, khoa: c.id, kichThuoc: 44)
                            Text((c.laNhomBool ? "👥 " : "") + (c.ten ?? c.id))
                        }
                    }
                }
            }
            .navigationTitle("Danh bạ")
            .navigationDestination(for: Cuoc.self) { c in ChatView(cuoc: c) }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await lamMoi() }
                    } label: {
                        if dangLamMoi { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
            .task { await tai() }
            .refreshable { await tai() }
        }
    }

    private func tai() async {
        dangTai = true
        defer { dangTai = false }
        ds = (try? await env.api.dsCuoc()) ?? ds
    }

    private func lamMoi() async {
        dangLamMoi = true
        defer { dangLamMoi = false }
        if let so = try? await env.api.lamMoiDanhBa().so {
            thongBao = "Đã nạp thêm \(so) liên hệ từ Zalo"
        }
        await tai()
    }
}
