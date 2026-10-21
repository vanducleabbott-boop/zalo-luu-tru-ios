import SwiftUI

struct ZaloQRLoginView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var dangTaoQR = false
    @State private var thongBaoLoi: String? = nil

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

                            VStack(spacing: 6) {
                                Text("Quét mã QR bằng Zalo")
                                    .font(.headline)
                                Text("1. Mở app Zalo trên điện thoại\n2. Bấm biểu tượng QR ở góc trên\n3. Quét mã này và xác nhận Đăng nhập")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
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
            .navigationTitle("Đăng nhập Zalo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .task {
                await env.kiemTraTrangThaiZalo()
                if env.zaloServerStatus?.daDangNhap != true && env.zaloServerStatus?.qr == nil {
                    await batDauDangNhap()
                }
            }
        }
    }

    private func batDauDangNhap() async {
        dangTaoQR = true
        thongBaoLoi = nil
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
