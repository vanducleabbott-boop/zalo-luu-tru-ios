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
    @State private var dungLuongCache = "0 MB"
    @State private var hienXacNhanXoaCache = false
    @State private var hienSheetQuetQR = false
    @State private var lamMoiCloudflare = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Máy chủ & Kết nối Realtime") {
                    if dangSua {
                        TextField("https://zalo.nhaduc.name.vn", text: $diaChi)
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
                Section("Cloudflare") {
                    LabeledContent("Phiên hết hạn", value: thoiHanCloudflare)
                    Button("Đăng nhập lại Cloudflare") {
                        CloudflareAccess.clear()
                        lamMoiCloudflare.toggle()
                        CloudflareAccess.shared.requestLogin(baseURL: env.settings.baseURL)
                    }
                }
                Section("Đăng nhập Zalo Web (Máy chủ)") {
                    HStack {
                        Text("Trạng thái")
                        Spacer()
                        if let st = env.zaloServerStatus {
                            if st.daDangNhap {
                                Text("🟢 \(st.ten ?? "Đã đăng nhập")")
                                    .font(.footnote)
                                    .foregroundStyle(.green)
                            } else {
                                Text(st.trangThai == "cho_quet_qr" ? "🟡 Đang chờ quét QR" : "🔴 Chưa đăng nhập")
                                    .font(.footnote)
                                    .foregroundStyle(st.trangThai == "cho_quet_qr" ? .orange : .red)
                            }
                        } else {
                            Text("Đang kiểm tra...").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if let uid = env.zaloServerStatus?.uid, !uid.isEmpty {
                        HStack {
                            Text("UID")
                            Spacer()
                            Text(uid).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        hienSheetQuetQR = true
                    } label: {
                        HStack {
                            Image(systemName: "qrcode.viewfinder")
                            Text(env.zaloServerStatus?.daDangNhap == true ? "Đăng nhập lại Zalo Web (Tải mã QR)" : "Đăng nhập Zalo Web (Tải mã QR)")
                                .fontWeight(.semibold)
                        }
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
                Section("Giao diện & Tin nhắn") {
                    Text("Giao diện: Theo hệ thống (Cài đặt > Màn hình & Độ sáng của iPhone)").font(.footnote).foregroundStyle(.secondary)
                    Toggle("Xem tin nhắn đã thu hồi", isOn: $env.hienTinThuHoi)
                    Text("Tự động lưu và hiển thị toàn bộ nội dung tin nhắn, ảnh, video của người khác ngay cả khi họ đã bấm thu hồi.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Section("Bộ nhớ đệm iPhone") {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Ảnh, video, tệp tin & tin nhắn")
                            Text("• Tin nhắn: Tải sẵn trên máy mở tức thì\n• Ảnh & video: Tự lưu 30 ngày gần đây\n• Tệp tin (file): Tự lưu 7 ngày gần đây\n• Cũ hơn: Tải về khi bấm vào xem").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(dungLuongCache).foregroundStyle(.secondary)
                    }
                    Button("Xoá toàn bộ bộ nhớ đệm") {
                        hienXacNhanXoaCache = true
                    }
                    .font(.footnote)
                }
                Section("Thông tin ứng dụng") {
                    HStack {
                        Text("Phiên bản")
                        Spacer()
                        // đọc từ Info.plist (trước viết cứng "3.4 (Build 30)" nên cài bản nào cũng hiện 3.4)
                        Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button("Đăng xuất", role: .destructive) { hienXacNhanDangXuat = true }
                }
            }
            .navigationTitle("Cá nhân")
            .confirmationDialog("Xoá toàn bộ bộ nhớ đệm ảnh, video, tệp tin & tin nhắn?", isPresented: $hienXacNhanXoaCache, titleVisibility: .visible) {
                Button("Xoá bộ nhớ đệm", role: .destructive) {
                    MediaDiskCache.shared.xoaToanBoCache()
                    ImageCacheManager.shared.xoaCache()
                    TinNhanDiskCache.shared.xoaToanBo()
                    dungLuongCache = MediaDiskCache.shared.dungLuongDinhDang()
                }
                Button("Huỷ", role: .cancel) {}
            }
            .confirmationDialog("Đăng xuất khỏi Zalo lưu trữ?", isPresented: $hienXacNhanDangXuat, titleVisibility: .visible) {
                Button("Đăng xuất", role: .destructive) { env.dangXuat() }
                Button("Huỷ", role: .cancel) {}
            }
            .sheet(isPresented: $hienSheetQuetQR) {
                ZaloQRLoginView()
            }
            .onAppear {
                kiemTraTrangThaiThongBao()
                dungLuongCache = MediaDiskCache.shared.dungLuongDinhDang()
                lamMoiCloudflare.toggle()
                Task { await env.kiemTraTrangThaiZalo() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                kiemTraTrangThaiThongBao()
            }
            .onReceive(NotificationCenter.default.publisher(for: CloudflareAccess.didLoginNotification)) { _ in
                lamMoiCloudflare.toggle()
            }
        }
    }

    private var thoiHanCloudflare: String {
        _ = lamMoiCloudflare
        if let exp = CloudflareAccess.expiryDate {
            return CloudflareAccess.formatExpiry(exp)
        }
        return "chưa đăng nhập"
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
