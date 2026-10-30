import SwiftUI

@main
struct ZaloLuuTruApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject private var access = CloudflareAccess.shared
    @State private var canhBaoHetHan: Bool = false
    @State private var thoiGianHetHanChuoi: String = ""

    var body: some View {
        Group {
            if env.dangKiemTraPhien {
                ProgressView()
            } else if env.daDangNhap {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if canhBaoHetHan {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.footnote)
                    Text("Phiên Cloudflare hết hạn \(thoiGianHetHanChuoi)")
                        .font(.footnote)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button("Đăng nhập lại") {
                        CloudflareAccess.clear(caTaiKhoan: true)
                        CloudflareAccess.shared.requestLogin(baseURL: env.settings.baseURL)
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Color.yellow.opacity(0.18))
                .overlay(Divider(), alignment: .bottom)
            }
        }
        // v7.1: tệp chia sẻ vào app -> chọn người/nhóm để gửi (đợi đăng nhập xong mới hiện)
        .onOpenURL { url in
            if let t = TepNhanDuoc.doc(url) { env.tepNhanDuoc.append(t) }
        }
        .sheet(isPresented: Binding(get: { env.daDangNhap && !env.tepNhanDuoc.isEmpty && !access.showLogin },
                                    set: { if !$0 { env.tepNhanDuoc = [] } })) {
            NhanTepChiaSeView().environmentObject(env)
        }
        .sheet(isPresented: $access.showLogin) {
            CloudflareLoginSheet(baseURL: access.loginURL ?? env.settings.baseURL) {
                capNhatCanhBao()
            }
        }
        .onAppear {
            env.kiemTraPhienDaCo()
            capNhatCanhBao()
        }
        .onReceive(NotificationCenter.default.publisher(for: CloudflareAccess.didLoginNotification)) { _ in
            capNhatCanhBao()
        }
        .onChange(of: access.showLogin) { _ in
            capNhatCanhBao()
        }
    }

    private func capNhatCanhBao() {
        canhBaoHetHan = CloudflareAccess.daysLeftWarning
        if let exp = CloudflareAccess.expiryDate {
            thoiGianHetHanChuoi = CloudflareAccess.formatExpiry(exp)
        } else {
            thoiGianHetHanChuoi = ""
        }
    }
}
