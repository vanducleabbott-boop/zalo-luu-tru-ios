import SwiftUI

final class ImageSaver: NSObject {
    var onSuccess: (() -> Void)?
    var onError: ((Error) -> Void)?

    init(onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        self.onSuccess = onSuccess
        self.onError = onError
    }

    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        DispatchQueue.main.async {
            if let error = error {
                self.onError?(error)
            } else {
                self.onSuccess?()
            }
        }
    }
}

struct ZaloQRLoginView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var dangTaoQR = false
    @State private var thongBaoLoi: String? = nil
    @State private var daLuuAnh = false
    @State private var thongBaoLuuAnh: String? = nil
    @State private var hienXacNhanDangNhapLai = false
    @State private var saverHolder: ImageSaver?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                if let st = env.zaloServerStatus {
                    if st.daDangNhap {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(.green)
                            Text("Đã đăng nhập Zalo!")
                                .font(.title2.bold())
                            if let ten = st.ten, !ten.isEmpty {
                                Text(ten)
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Máy chủ đang lưu tin nhắn và phục vụ ứng dụng bình thường.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)

                            Button {
                                hienXacNhanDangNhapLai = true
                            } label: {
                                Label("Đăng nhập lại (Tạo mã QR mới)", systemImage: "arrow.clockwise")
                                    .font(.subheadline.bold())
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.bordered)
                            .padding(.top, 10)
                        }
                    } else if st.trangThai == "da_quet" {
                        VStack(spacing: 14) {
                            ProgressView()
                                .scaleEffect(1.6)
                                .padding()
                            Text("📱 Đã quét mã QR!")
                                .font(.title3.bold())
                            if let ten = st.ten, !ten.isEmpty {
                                Text("Tài khoản: \(ten)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Vui lòng bấm Đăng nhập trên màn hình điện thoại để hoàn tất.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    } else if let qrStr = st.qr, let img = anhTuBase64(qrStr) {
                        VStack(spacing: 14) {
                            Image(uiImage: img)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 220, height: 220)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                                .shadow(radius: 4)

                            HStack(spacing: 12) {
                                Button {
                                    luuAnhVaoThuVien(img)
                                } label: {
                                    Label(daLuuAnh ? "Đã lưu vào Ảnh" : "Tải / Lưu mã QR vào Ảnh", systemImage: daLuuAnh ? "checkmark.circle.fill" : "square.and.arrow.down")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(daLuuAnh ? Color.green : Color.blue)
                                        .clipShape(Capsule())
                                }

                                ShareLink(item: Image(uiImage: img), preview: SharePreview("Mã QR đăng nhập Zalo", image: Image(uiImage: img))) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.subheadline.bold())
                                        .padding(10)
                                        .background(Color.secondary.opacity(0.15))
                                        .clipShape(Circle())
                                }
                            }

                            if let thongBao = thongBaoLuuAnh {
                                Text(thongBao)
                                    .font(.caption)
                                    .foregroundStyle(daLuuAnh ? .green : .red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Cách quét mã QR trên điện thoại:")
                                    .font(.footnote.bold())
                                Text("1. Bấm nút **Tải / Lưu mã QR vào Ảnh** ở trên\n2. Mở app **Zalo** > Bấm biểu tượng **Quét mã QR** (góc trên)\n3. Bấm **Chọn ảnh từ thư viện** và chọn ảnh mã QR vừa lưu\n4. Bấm **Đăng nhập** để xác nhận")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Button {
                                    if let url = URL(string: "zalo://"), UIApplication.shared.canOpenURL(url) {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    HStack {
                                        Spacer()
                                        Label("Mở ứng dụng Zalo", systemImage: "arrow.up.right.square.fill")
                                            .font(.footnote.bold())
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .padding(.top, 4)
                            }
                            .padding(.horizontal, 24)
                        }
                    } else if dangTaoQR {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.4)
                            Text("Đang tạo mã QR...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 60))
                                .foregroundStyle(.secondary)
                            Text("Chưa có mã QR")
                                .font(.headline)
                            if let loi = st.loi ?? thongBaoLoi {
                                Text(loi)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }
                            Button("Tạo mã QR đăng nhập") {
                                Task { await batDauDangNhap() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else if dangTaoQR {
                    VStack(spacing: 12) {
                        ProgressView().scaleEffect(1.4)
                        Text("Đang kết nối máy chủ...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text("Đăng nhập Zalo Web")
                            .font(.title3.bold())
                        Text("Kết nối tài khoản Zalo với máy chủ lưu trữ.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Bắt đầu quét mã") {
                            Task { await batDauDangNhap() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Spacer()

                if let st = env.zaloServerStatus, !st.daDangNhap {
                    HStack(spacing: 16) {
                        Button("Lấy mã mới") {
                            Task { await batDauDangNhap() }
                        }
                        .font(.footnote)
                        .disabled(dangTaoQR)

                        if st.trangThai == "cho_quet_qr" {
                            Button("Huỷ quét", role: .destructive) {
                                Task {
                                    try? await env.api.huyDangNhapZalo()
                                    await env.kiemTraTrangThaiZalo()
                                }
                            }
                            .font(.footnote)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("Đăng nhập Zalo Web")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .confirmationDialog("Đăng nhập lại Zalo Web?", isPresented: $hienXacNhanDangNhapLai, titleVisibility: .visible) {
                Button("Tạo mã QR mới", role: .destructive) {
                    Task { await batDauDangNhap() }
                }
                Button("Huỷ", role: .cancel) {}
            } message: {
                Text("Tạo mã QR mới để quét bằng tài khoản Zalo khác hoặc làm mới phiên đăng nhập máy chủ.")
            }
            .task {
                await env.kiemTraTrangThaiZalo()
                if env.zaloServerStatus?.daDangNhap != true && env.zaloServerStatus?.qr == nil {
                    await batDauDangNhap()
                }
            }
        }
    }

    private func luuAnhVaoThuVien(_ img: UIImage) {
        let saver = ImageSaver(
            onSuccess: {
                daLuuAnh = true
                thongBaoLuuAnh = "✅ Đã lưu mã QR vào Thư viện ảnh! Mở Zalo quét từ ảnh."
            },
            onError: { err in
                daLuuAnh = false
                thongBaoLuuAnh = "❌ Lỗi lưu ảnh: \(err.localizedDescription)"
            }
        )
        self.saverHolder = saver
        UIImageWriteToSavedPhotosAlbum(img, saver, #selector(ImageSaver.image(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    private func batDauDangNhap() async {
        dangTaoQR = true
        thongBaoLoi = nil
        daLuuAnh = false
        thongBaoLuuAnh = nil
        defer { dangTaoQR = false }
        do {
            let st = try await env.api.yeuCauDangNhapZalo()
            env.zaloServerStatus = st
        } catch {
            thongBaoLoi = error.localizedDescription
        }
    }

    private func anhTuBase64(_ chuoi: String) -> UIImage? {
        let raw: String
        if let range = chuoi.range(of: "base64,") {
            raw = String(chuoi[range.upperBound...])
        } else {
            raw = chuoi
        }
        guard let data = Data(base64Encoded: raw, options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)
    }
}
