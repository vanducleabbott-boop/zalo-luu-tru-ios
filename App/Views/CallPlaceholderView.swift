import SwiftUI
import WebKit
import AVFoundation

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
        .onAppear {
            cauHinhAudioSession()
        }
    }

    private func cauHinhAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("Lỗi cấu hình AVAudioSession: \(error)")
        }
    }
}

private struct CallWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let cauHinh = WKWebViewConfiguration()
        cauHinh.allowsInlineMediaPlayback = true
        cauHinh.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: cauHinh)
        web.uiDelegate = context.coordinator
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

    class Coordinator: NSObject, WKUIDelegate {
        @available(iOS 15.0, *)
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            decisionHandler(.grant)
        }
    }
}
