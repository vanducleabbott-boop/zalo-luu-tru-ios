import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var diaChi = ""
    @State private var dangSua = false
    @State private var hienXacNhanDangXuat = false
    @State private var trangThaiThongBao = "Đang kiểm tra..."
    @State private var daCapQuyenThongBao = false
    @State private var canMoCaiDat = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Máy chủ & Kết nối Realtime") {
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
                    HStack {
                        Text("Kết nối thời gian thực")
                        Spacer()
                        Text(env.sse.daKetNoi ? "🟢 Đang kết nối" : "🔴 \(env.sse.thongBaoTrangThai)")
                            .font(.footnote)
                            .foregroundStyle(env.sse.daKetNoi ? .green : .red)
                    }
                    if !env.sse.daKetNoi {
                        Button("Thử kết nối lại realtime ngay") {
                            env.sse.batDau(api: env.api)
                        }
                        .font(.footnote)
                    }
                }
                Section("Thông báo") {
                    HStack {
                        Text("Quyền thông báo")
                        Spacer()
                        Text(trangThaiThongBao)
                            .foregroundStyle(mauTrangThaiThongBao)
                    }
                    if canMoCaiDat {
                        Button("Mở Cài đặt hệ thống để cấp quyền") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    } else if !daCapQuyenThongBao {
                        Button("Bật thông báo ngay") {
                            NotificationManager.shared.xinQuyen { chapNhan in
                                kiemTraTrangThaiThongBao()
                            }
                        }
                    }
                    Button("Gửi thông báo thử nghiệm (sau 2 giây)") {
                        NotificationManager.shared.guiThongBaoThu()
                    }
                }
                Section("Giao diện") {
                    Text("Theo hệ thống (Cài đặt > Màn hình & Độ sáng của iPhone)").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Thông tin ứng dụng") {
                    HStack {
                        Text("Phiên bản")
                        Spacer()
                        Text("1.6 (Build 7)").foregroundStyle(.secondary)
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
            .onAppear {
                kiemTraTrangThaiThongBao()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                kiemTraTrangThaiThongBao()
            }
        }
    }

    private var mauTrangThaiThongBao: Color {
        daCapQuyenThongBao ? .green : .secondary
    }

    private func kiemTraTrangThaiThongBao() {
        NotificationManager.shared.kiemTraQuyen { status in
            switch status {
            case .authorized, .provisional:
                trangThaiThongBao = "Đang bật"
                daCapQuyenThongBao = true
                canMoCaiDat = false
            case .denied:
                trangThaiThongBao = "Bị tắt trong Cài đặt iPhone"
                daCapQuyenThongBao = false
                canMoCaiDat = true
            case .notDetermined:
                trangThaiThongBao = "Chưa cấp quyền"
                daCapQuyenThongBao = false
                canMoCaiDat = false
            @unknown default:
                trangThaiThongBao = "Không rõ"
                daCapQuyenThongBao = false
                canMoCaiDat = false
            }
        }
    }
}
