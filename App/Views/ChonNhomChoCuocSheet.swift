// Sheet chọn nhóm để đưa một cuộc trò chuyện vào một hoặc nhiều nhóm tuỳ chọn.

import SwiftUI

struct ChonNhomChoCuocSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = NhomChatManager.shared

    let cuoc: Cuoc

    @State private var cacNhomDaChon: Set<String> = []
    @State private var tenNhomMoi = ""
    @State private var hienOtaoMoi = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        AvatarView(ten: cuoc.ten ?? cuoc.id, anh: cuoc.anh, khoa: cuoc.id, kichThuoc: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text((cuoc.laNhomBool ? "👥 " : "") + (cuoc.ten ?? cuoc.id))
                                .font(.headline)
                                .lineLimit(1)
                            Text(cuoc.laNhomBool ? "Nhóm Zalo" : "Trò chuyện cá nhân")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Đoạn chat được chọn")
                }

                Section {
                    ForEach(manager.dsNhom) { nhom in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(ZaloMau.xanh)
                                .font(.system(size: 18))

                            Text(nhom.ten)
                                .font(.body)

                            Spacer()

                            if cacNhomDaChon.contains(nhom.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(ZaloMau.xanh)
                                    .font(.system(size: 20))
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(Color(.systemGray4))
                                    .font(.system(size: 20))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleNhom(nhom.id)
                        }
                    }

                    if hienOtaoMoi {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                                .foregroundStyle(.secondary)
                            TextField("Tên nhóm (ví dụ: Đặt hàng, Khách VIP)…", text: $tenNhomMoi)
                                .textInputAutocapitalization(.words)
                            Button("Thêm") {
                                taoVaChonNhomMoi()
                            }
                            .bold()
                            .disabled(tenNhomMoi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    } else {
                        Button {
                            hienOtaoMoi = true
                        } label: {
                            Label("Tạo nhóm phân loại mới", systemImage: "plus.circle.fill")
                                .foregroundStyle(ZaloMau.xanh)
                        }
                    }
                } header: {
                    Text("Nhóm phân loại")
                } footer: {
                    Text("Một đoạn chat có thể thuộc về nhiều nhóm phân loại khác nhau.")
                }
            }
            .navigationTitle("Chọn nhóm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Xong") {
                        luuVaDong()
                    }
                    .bold()
                }
            }
            .onAppear {
                cacNhomDaChon = manager.dsNhomIdCuaCuoc(cuocId: cuoc.id)
            }
        }
    }

    private func toggleNhom(_ nhomId: String) {
        if cacNhomDaChon.contains(nhomId) {
            cacNhomDaChon.remove(nhomId)
        } else {
            cacNhomDaChon.insert(nhomId)
        }
        manager.datNhomChoCuoc(cuocId: cuoc.id, cacNhomId: cacNhomDaChon)
    }

    private func taoVaChonNhomMoi() {
        let ten = tenNhomMoi.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ten.isEmpty else { return }
        let moi = manager.taoNhom(ten: ten)
        cacNhomDaChon.insert(moi.id)
        manager.datNhomChoCuoc(cuocId: cuoc.id, cacNhomId: cacNhomDaChon)
        tenNhomMoi = ""
        hienOtaoMoi = false
    }

    private func luuVaDong() {
        manager.datNhomChoCuoc(cuocId: cuoc.id, cacNhomId: cacNhomDaChon)
        dismiss()
    }
}
