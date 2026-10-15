import UIKit
import WebKit
import AVFoundation
import UserNotifications

// Địa chỉ trang web lưu trữ (Tailscale HTTPS). iPhone phải bật Tailscale.
let DIA_CHI = URL(string: "https://desktop-krdjkc2.tailbd558a.ts.net:8443/")!

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Âm thanh kiểu cuộc gọi: nghe + nói, chạy tiếp khi ra màn hình chính
        let phien = AVAudioSession.sharedInstance()
        try? phien.setCategory(.playAndRecord, mode: .voiceChat,
                               options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = ManHinhChinh()
        window?.makeKeyAndVisible()
        return true
    }
}

class ManHinhChinh: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
    var web: WKWebView!
    let lamMoi = UIRefreshControl()
    var fileDangTai: [WKDownload: URL] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1) : .white }

        let cauHinh = WKWebViewConfiguration()
        cauHinh.allowsInlineMediaPlayback = true
        cauHinh.mediaTypesRequiringUserActionForPlayback = []
        cauHinh.websiteDataStore = .default()
        cauHinh.applicationNameForUserAgent = "ZaloLuuTruApp/1.0"
        // Cầu cho trang gọi: window.ZaloApp.thongBao(tieuDe, noiDung)
        let cau = """
        window.ZaloApp = { laApp: true, thongBao: function(t, n) {
          window.webkit.messageHandlers.zaloApp.postMessage({loai: 'thongBao', tieuDe: String(t || ''), noiDung: String(n || '')});
        }};
        """
        cauHinh.userContentController.addUserScript(WKUserScript(source: cau, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cauHinh.userContentController.add(self, name: "zaloApp")

        web = WKWebView(frame: .zero, configuration: cauHinh)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = view.backgroundColor
        if #available(iOS 16.4, *) { web.isInspectable = true }
        lamMoi.addTarget(self, action: #selector(taiLai), for: .valueChanged)
        web.scrollView.refreshControl = lamMoi

        web.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(web)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            web.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        web.load(URLRequest(url: DIA_CHI))
    }

    @objc func taiLai() {
        if web.url == nil || web.url?.scheme == "about" { web.load(URLRequest(url: DIA_CHI)) } else { web.reload() }
    }

    // Mic/camera cho cuộc gọi: cho phép luôn với trang của mình
    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(origin.host == DIA_CHI.host ? .grant : .prompt)
    }

    // Link ngoài trang (zalo.me, zalo://, tel:, trang khác) mở bằng app tương ứng
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.allow) }
        if action.shouldPerformDownload { return decisionHandler(.download) }
        if url.host == DIA_CHI.host || url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" {
            return decisionHandler(.allow)
        }
        if action.targetFrame?.isMainFrame == false { return decisionHandler(.allow) }
        UIApplication.shared.open(url)
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let dinhKem = (response.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased().contains("attachment") ?? false
        decisionHandler(dinhKem || !response.canShowMIMEType ? .download : .allow)
    }

    // target=_blank: cùng trang thì mở tại chỗ, khác thì ra ngoài
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url {
            if url.host == DIA_CHI.host { webView.load(action.request) } else { UIApplication.shared.open(url) }
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { lamMoi.endRefreshing() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { baoLoi(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { baoLoi(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

    func baoLoi(_ loi: Error) {
        lamMoi.endRefreshing()
        if (loi as NSError).code == NSURLErrorCancelled { return }
        let html = """
        <html><head><meta name='viewport' content='width=device-width,initial-scale=1'>
        <style>body{font-family:-apple-system;padding:40px 24px;text-align:center;color:#888}
        @media(prefers-color-scheme:dark){body{background:#1e1f23;color:#aaa}}
        a{display:inline-block;margin-top:20px;padding:12px 28px;background:#0068ff;color:#fff;border-radius:10px;text-decoration:none}</style></head>
        <body><h3>Không vào được máy chủ</h3><p>Kiểm tra Tailscale trên iPhone đã bật và máy tính đang mở.</p>
        <p style='font-size:12px'>\(loi.localizedDescription)</p><a href='\(DIA_CHI.absoluteString)'>Thử lại</a></body></html>
        """
        web.loadHTMLString(html, baseURL: nil)
    }

    // Hộp thoại JS
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(a, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Huỷ", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(a, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        a.addTextField { $0.text = defaultText }
        a.addAction(UIAlertAction(title: "Huỷ", style: .cancel) { _ in completionHandler(nil) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
        present(a, animated: true)
    }

    // Tải file: lưu vào Tệp (Files) rồi mở bảng chia sẻ
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let thuMuc = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var dich = thuMuc.appendingPathComponent(suggestedFilename)
        var i = 1
        while FileManager.default.fileExists(atPath: dich.path) {
            let ten = (suggestedFilename as NSString).deletingPathExtension
            let duoi = (suggestedFilename as NSString).pathExtension
            dich = thuMuc.appendingPathComponent("\(ten) (\(i))" + (duoi.isEmpty ? "" : ".\(duoi)"))
            i += 1
        }
        fileDangTai[download] = dich
        completionHandler(dich)
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard let url = fileDangTai.removeValue(forKey: download) else { return }
        let chiaSe = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        chiaSe.popoverPresentationController?.sourceView = view
        present(chiaSe, animated: true)
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        fileDangTai.removeValue(forKey: download)
    }

    // Thông báo cục bộ (chỉ chạy khi app còn sống, kể cả đang ở nền)
    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let d = message.body as? [String: Any], d["loai"] as? String == "thongBao" else { return }
        let nd = UNMutableNotificationContent()
        nd.title = d["tieuDe"] as? String ?? ""
        nd.body = d["noiDung"] as? String ?? ""
        nd.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: nd, trigger: nil))
    }
}
