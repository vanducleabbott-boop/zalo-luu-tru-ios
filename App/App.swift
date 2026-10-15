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
        .onAppear { env.kiemTraPhienDaCo() }
    }
}
