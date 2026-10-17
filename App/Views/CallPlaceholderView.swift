// GIAI ĐOẠN 2 (chưa làm ở bản này): cuộc gọi qua cầu nối /api/goi/* đang được hoàn thiện ở phía máy chủ/web
// (KHÔNG đụng tới web_zalo.mjs / web/index.html trong lượt việc này). Tạm thời mở trang web cũ
// (đã có sẵn nút "📞 Cuộc gọi Zalo PC") trong WKWebView, đồng bộ cookie phiên để khỏi đăng nhập lại.

import SwiftUI
import WebKit

struct CallPlaceholderView: View {
    @EnvironmentObject var env: AppEnvironment

    private var callURL: URL {
        URL(string: "https://desktop-krdjkc2.tailbd558a.ts.net:3456")!
    }

    var body: some View {
        NavigationStack {
            CallWebView(url: callURL)
                .navigationTitle("Cuộc gọi")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct CallWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let cauHinh = WKWebViewConfiguration()
        cauHinh.allowsInlineMediaPlayback = true
        cauHinh.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: cauHinh)
        taiTrang(web)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    /// Chép cookie phiên "zw" từ HTTPCookieStorage.shared (do ZaloAPI dùng) sang kho cookie riêng của WKWebView,
    /// để trang web không bắt đăng nhập lại mật khẩu lần nữa.
    private func taiTrang(_ web: WKWebView) {
        let coKhop = HTTPCookieStorage.shared.cookies(for: url) ?? []
        let kho = WKWebsiteDataStore.default().httpCookieStore
        let nhom = DispatchGroup()
        for c in coKhop { nhom.enter(); kho.setCookie(c) { nhom.leave() } }
        nhom.notify(queue: .main) { web.load(URLRequest(url: url)) }
    }
}
