// Kết nối thật tới /api/su-kien bằng URLSession.bytes(for:), dùng SSEParser ở trên để tách sự kiện.
// Theo dõi "lần cuối nghe được gì" (kể cả nhịp 15s) để lớp gọi (SSEManager) quyết định khi nào nối lại.

import Foundation

actor SSEClient {
    private let url: URL
    private var task: Task<Void, Never>?

    init(url: URL) {
        self.url = url
    }

    /// Mở kết nối và gọi `onEvent` cho mỗi sự kiện nhận được, cho tới khi `dong()` được gọi hoặc kết nối lỗi (onClosed).
    func mo(onEvent: @escaping @Sendable (SuKienSSE) -> Void, onClosed: @escaping @Sendable (Error?) -> Void) {
        dong()
        task = Task {
            var req = URLRequest(url: url)
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 70   // nhịp máy chủ 15s, im quá ~60-70s coi như đứt
            let parser = SSEParser()
            do {
                let (byteStream, response) = try await URLSession.shared.bytes(for: req)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    onClosed(NSError(domain: "SSEClient", code: http.statusCode))
                    return
                }
                // Gom theo BYTE (khong phai Character) roi moi giai ma UTF-8 ca dong: tin Zalo luon co chu tieng Viet
                // co dau (UTF-8 nhieu byte) - tach tung byte thanh 1 UnicodeScalar rieng se lam hong cac ky tu nay.
                // Ky tu "\n" (0x0A) khong bao gio la byte noi tiep cua UTF-8 nen cat o do luon an toan.
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
                onClosed(nil)
            } catch {
                if Task.isCancelled { return }
                onClosed(error)
            }
        }
    }

    func dong() {
        task?.cancel()
        task = nil
    }
}

/// Hàm thuần (không mạng, test được): có nên chủ động nối lại SSE không, dựa trên lần cuối nghe được gì.
/// Khớp web: `Date.now() - lanNghe > 40000` (trong setInterval 5s) hoặc khi app vừa lên foreground và quá hạn.
func canReconnectSSE(lastHeard: Date, now: Date, nguongGiay: TimeInterval = 40) -> Bool {
    now.timeIntervalSince(lastHeard) > nguongGiay
}
