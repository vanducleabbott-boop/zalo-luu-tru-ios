import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var diaChi = ""
    @State private var dangSua = false
    @State private var hienXacNhanDangXuat = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Máy chủ") {
                    if dangSua {
                        TextField("https://...", text: $diaChi)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        HStack {
                            Button("Lưu") { env.doiMayChu(diaChi); dangSua = false }
                            Button("Huỷ", role: .cancel) { dangSua = false }
                        }
                    } else {
                        HStack {
                            Text(env.settings.diaChiMayChu).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            Button("Sửa") { diaChi = env.settings.diaChiMayChu; dangSua = true }
                        }
                    }
                }
                Section("Giao diện") {
                    Text("Theo hệ thống (Cài đặt > Màn hình & Độ sáng của iPhone)").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Thông tin ứng dụng") {
                    HStack {
                        Text("Phiên bản")
                        Spacer()
                        Text("1.2 (Build 3)").foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button("Đăng xuất", role: .destructive) { hienXacNhanDangXuat = true }
                }
            }
            .navigationTitle("Cá nhân")
            .confirmationDialog("Đăng xuất khỏi Zalo lưu trữ?", isPresented: $hienXacNhanDangXuat, titleVisibility: .visible) {
                Button("Đăng xuất", role: .destructive) { env.dangXuat() }
                Button("Huỷ", role: .cancel) {}
            }
        }
    }
}
