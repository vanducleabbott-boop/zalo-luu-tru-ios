// Kết nối thật tới /api/su-kien bằng URLSession.bytes(for:), dùng SSEParser ở trên để tách sự kiện.
// Theo dõi "lần cuối nghe được gì" (kể cả nhịp 15s) để lớp gọi (SSEManager) quyết định khi nào nối lại.

import Foundation

actor SSEClient {
    private let url: URL
    private let tokenPhien: String?
    private var task: Task<Void, Never>?
    private var session: URLSession?

    init(url: URL, token: String? = nil) {
        self.url = url
        self.tokenPhien = token
    }

    /// Mở kết nối và gọi `onEvent` cho mỗi sự kiện nhận được, cho tới khi `dong()` được gọi hoặc kết nối lỗi (onClosed).
    func mo(onEvent: @escaping @Sendable (SuKienSSE) -> Void, onClosed: @escaping @Sendable (Error?) -> Void) {
        dong()
        let cau = URLSessionConfiguration.default
        cau.timeoutIntervalForRequest = 90
        cau.timeoutIntervalForResource = 86400   // Giữ luồng stream 24h
        cau.httpCookieStorage = HTTPCookieStorage.shared
        cau.httpShouldSetCookies = true
        let sess = URLSession(configuration: cau)
        self.session = sess

        task = Task {
            var req = URLRequest(url: url)
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            if let token = tokenPhien, !token.isEmpty {
                req.setValue("zw=\(token)", forHTTPHeaderField: "Cookie")
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            req.timeoutInterval = 90
            let parser = SSEParser()
            do {
                print("[SSE] Mo ket noi toi: \(url.absoluteString)")
                let (byteStream, response) = try await sess.bytes(for: req)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    print("[SSE] Loi HTTP status:", http.statusCode)
                    if !Task.isCancelled {
                        onClosed(NSError(domain: "SSEClient", code: http.statusCode))
                    }
                    return
                }
                print("[SSE] Da mo ket noi su kien thanh cong (HTTP 200)")
                var dongHienTai: [UInt8] = []
                for try await byte in byteStream {
                    if Task.isCancelled { return }
                    if byte == 0x0A {
                        if dongHienTai.last == 0x0D { dongHienTai.removeLast() }
                        let s = String(decoding: dongHienTai, as: UTF8.self)
                        if let sk = parser.feed(line: s) { onEvent(sk) }
                        dongHienTai.removeAll(keepingCapacity: true)
                    } else {
                        dongHienTai.append(byte)
                    }
                }
                if !Task.isCancelled {
                    onClosed(nil)
                }
            } catch {
                if !Task.isCancelled {
                    onClosed(error)
                }
            }
        }
    }

    func dong() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }
}

/// Hàm thuần (không mạng, test được): có nên chủ động nối lại SSE không, dựa trên lần cuối nghe được gì.
/// Khớp web: `Date.now() - lanNghe > 40000` (trong setInterval 5s) hoặc khi app vừa lên foreground và quá hạn.
func canReconnectSSE(lastHeard: Date, now: Date, nguongGiay: TimeInterval = 40) -> Bool {
    now.timeIntervalSince(lastHeard) > nguongGiay
}
