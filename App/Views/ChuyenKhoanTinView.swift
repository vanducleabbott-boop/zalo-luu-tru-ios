// Thẻ hiển thị thông tin chuyển khoản ngân hàng & mã QR VietQR (chuẩn NAPAS/VietQR).
// Tự động nhận diện hoặc hiển thị từ tin nhắn chuyển khoản.

import SwiftUI
import UIKit
import Photos

struct ChuyenKhoanTinView: View {
    let ck: ChuyenKhoanInfo
    @State private var daSaoChepSTK = false
    @State private var daSaoChepTatCa = false
    @State private var hienQRPopup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Logo / Tên ngân hàng & Huy hiệu VietQR
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.blue)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(ck.nganHang)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text("Chuyển khoản nhanh 24/7")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                }

                Spacer(minLength: 4)

                Text("VietQR")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.1), in: Capsule())
            }

            Divider()

            // Thông tin chi tiết
            VStack(alignment: .leading, spacing: 7) {
                // Hàng STK + Nút chép nhanh
                HStack(alignment: .center, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SỐ TÀI KHOẢN")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                        Text(ck.stk)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.primary)
                    }

                    Spacer()

                    Button {
                        UIPasteboard.general.string = ck.stk
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation { daSaoChepSTK = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { daSaoChepSTK = false }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: daSaoChepSTK ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11))
                            Text(daSaoChepSTK ? "Đã chép" : "Sao chép")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(daSaoChepSTK ? Color.green.opacity(0.15) : Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(daSaoChepSTK ? Color.green : Color.primary)
                    }
                    .buttonStyle(.plain)
                }

                // Chủ tài khoản
                if let ten = ck.tenNguoiNhan, !ten.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CHỦ TÀI KHOẢN")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                        Text(ten.uppercased())
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.primary)
                    }
                }

                // Số tiền
                if let soTien = ck.soTienDinhDang {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SỐ TIỀN")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                        Text(soTien)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.blue)
                    }
                }

                // Nội dung
                if let nd = ck.noiDung, !nd.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LỜI NHẮN / NỘI DUNG")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                        Text(nd)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary)
                    }
                }
            }

            // Khung mã QR
            Button {
                hienQRPopup = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)

                        // ảnh QR qua bộ đệm RAM/đĩa của app (AsyncImage tải lại mỗi lần ô tin được vẽ lại khi cuộn)
                        AnimatedImageView(url: URL(string: ck.qrUrl), contentMode: .scaleAspectFit, boGoc: 6)
                            .padding(4)
                    }
                    .frame(width: 86, height: 86)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 13, weight: .bold))
                            Text("Mã QR chuyển khoản")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Color.blue)

                        Text("Chạm để phóng to mã QR hoặc lưu ảnh vào thư viện để quét")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            // Nút sao chép tất cả
            Button {
                UIPasteboard.general.string = ck.thongTinSaoChep
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation { daSaoChepTatCa = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { daSaoChepTatCa = false }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: daSaoChepTatCa ? "checkmark.circle.fill" : "doc.on.doc.fill")
                        .font(.system(size: 12))
                    Text(daSaoChepTatCa ? "Đã sao chép toàn bộ thông tin" : "Sao chép toàn bộ thông tin CK")
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(daSaoChepTatCa ? Color.green.opacity(0.15) : Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(daSaoChepTatCa ? Color.green : Color.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(minWidth: 260, maxWidth: 300, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.systemGray4).opacity(0.6), lineWidth: 1)
        )
        .sheet(isPresented: $hienQRPopup) {
            QRPhongToView(ck: ck)
        }
    }
}

// ---------------------------------------------------------------- Màn hình phóng to mã QR
struct QRPhongToView: View {
    let ck: ChuyenKhoanInfo
    @Environment(\.dismiss) private var dismiss
    @State private var daLuuAnh = false
    @State private var dangLuu = false
    @State private var thongBaoLoi: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Thẻ trắng chứa mã QR
                    VStack(spacing: 14) {
                        Text(ck.nganHang)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.black)

                        ZStack {
                            Color.white
                            AnimatedImageView(url: URL(string: ck.qrUrl), contentMode: .scaleAspectFit, boGoc: 0)
                        }
                        .frame(width: 260, height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(spacing: 4) {
                            Text(ck.stk)
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.black)

                            if let ten = ck.tenNguoiNhan, !ten.isEmpty {
                                Text(ten.uppercased())
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.black.opacity(0.75))
                            }

                            if let soTien = ck.soTienDinhDang {
                                Text(soTien)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Color.blue)
                                    .padding(.top, 2)
                            }
                        }
                    }
                    .padding(20)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                    .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                    // Các nút hành động
                    VStack(spacing: 12) {
                        Button {
                            luuAnhVaoThuVien()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: daLuuAnh ? "checkmark.circle.fill" : "arrow.down.to.line.circle.fill")
                                    .font(.system(size: 16))
                                Text(daLuuAnh ? "Đã lưu vào Ảnh" : "Lưu ảnh QR vào máy")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(daLuuAnh ? Color.green : Color.blue, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(Color.white)
                        }
                        .disabled(dangLuu)

                        if let thongBaoLoi {
                            Text(thongBaoLoi).font(.footnote).foregroundStyle(Color.red).multilineTextAlignment(.center)
                        }

                        Button {
                            UIPasteboard.general.string = ck.stk
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 15))
                                Text("Sao chép số tài khoản")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(Color.primary)
                        }

                        Button {
                            UIPasteboard.general.string = ck.thongTinSaoChep
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "list.clipboard")
                                    .font(.system(size: 15))
                                Text("Sao chép toàn bộ thông tin CK")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(Color.secondary)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
            .navigationTitle("Mã QR chuyển khoản")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }

    private func luuAnhVaoThuVien() {
        guard let url = URL(string: ck.qrUrl) else { return }
        dangLuu = true
        thongBaoLoi = nil
        Task { @MainActor in
            defer { dangLuu = false }
            do {
                // ảnh đã hiện trên thẻ thì có sẵn trong bộ đệm đĩa, khỏi tải lại
                let data: Data
                if let coSan = MediaDiskCache.shared.layDuLieu(cho: url) { data = coSan }
                else { data = try await URLSession.shared.data(from: url).0 }
                guard let image = UIImage(data: data) else { thongBaoLoi = "Ảnh QR không hợp lệ"; return }
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                daLuuAnh = true
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            } catch {
                thongBaoLoi = "Không tải được ảnh: " + error.localizedDescription
            }
        }
    }
}
