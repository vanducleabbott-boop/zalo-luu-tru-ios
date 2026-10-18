import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $env.tabChon) {
                ConversationListView()
                    .tabItem { Label("Tin nhắn", systemImage: "message.fill") }
                    .tag(0)
                ContactsView()
                    .tabItem { Label("Danh bạ", systemImage: "person.2.fill") }
                    .tag(1)
                CallPlaceholderView()
                    .tabItem { Label("Cuộc gọi", systemImage: "phone.fill") }
                    .tag(2)
                SettingsView()
                    .tabItem { Label("Cá nhân", systemImage: "person.crop.circle.fill") }
                    .tag(3)
            }

            if let cuocGoi = env.cuocGoiHienTai {
                CuocGoiDenBannerView(cuocGoi: cuocGoi)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(999)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: env.cuocGoiHienTai)
    }
}

struct CuocGoiDenBannerView: View {
    @EnvironmentObject var env: AppEnvironment
    let cuocGoi: ThongTinCuocGoi
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Biểu tượng chuông/điện thoại nhấp nháy
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.3))
                        .frame(width: 46, height: 46)
                        .scaleEffect(pulse ? 1.25 : 0.9)
                        .opacity(pulse ? 0.3 : 0.8)
                    Circle()
                        .fill(Color.green)
                        .frame(width: 38, height: 38)
                    Image(systemName: "phone.fill")
                        .foregroundStyle(.white)
                        .font(.system(size: 18, weight: .semibold))
                        .rotationEffect(.degrees(pulse ? 15 : -15))
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cuộc gọi Zalo đến")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    Text(cuocGoi.nguon != nil ? "Đang reo trên PC (\(cuocGoi.nguon!))" : "Đang đổ chuông trên Zalo PC")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Nút từ chối
                Button {
                    env.tuChoiCuocGoi()
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.red)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Nút bốc máy
                Button {
                    env.bocMayTrenPC()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Bốc máy")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
            )
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
    }
}
