// Bộ đọc Server-Sent Events thuần (không phụ thuộc mạng) - khớp cách web_zalo.mjs phát:
//   "event: <loai>\ndata: <json>\n\n"  (có thể nhiều dòng "data:" cho 1 sự kiện - nối bằng "\n")
//   dòng bắt đầu ":" là comment (bị bỏ qua), dòng "retry: <ms>" đổi thời gian gợi ý nối lại.
// Thiết kế để test được: nạp từng DÒNG một (feed(line:)), không quan tâm việc dòng đó đến từ đâu.

import Foundation

struct SuKienSSE: Equatable {
    var loai: String   // mặc định "message" nếu không có dòng "event:"
    var data: String
    var id: String?
}

final class SSEParser {
    private(set) var loaiDangGom = "message"
    private var dongData: [String] = []
    private var idDangGom: String?
    private(set) var retryMs: Int?

    /// Nạp 1 dòng văn bản (đã bỏ CRLF/LF cuối dòng). Trả về sự kiện hoàn chỉnh nếu dòng này là dòng trống kết thúc khối.
    @discardableResult
    func feed(line: String) -> SuKienSSE? {
        if line.isEmpty {
            // dòng trống = hết 1 khối sự kiện
            guard !dongData.isEmpty else { resetKhoi(); return nil }
            let suKien = SuKienSSE(loai: loaiDangGom, data: dongData.joined(separator: "\n"), id: idDangGom)
            resetKhoi()
            return suKien
        }
        if line.hasPrefix(":") { return nil }   // comment / nhịp giữ kết nối kiểu ":keep-alive"
        let (truong, giaTri) = tachTruong(line)
        switch truong {
        case "event": loaiDangGom = giaTri
        case "data": dongData.append(giaTri)
        case "id": idDangGom = giaTri
        case "retry": retryMs = Int(giaTri)
        default: break   // truong la khong ro -> bo qua theo chuan SSE
        }
        return nil
    }

    /// Nạp 1 khối dữ liệu thô (có thể chứa nhiều dòng, cắt ở ranh giới bất kỳ, CRLF hay LF) -> trả về
    /// các sự kiện hoàn chỉnh theo thứ tự. Tách theo BYTE UTF-8 (không dùng String.split theo Character
    /// "\n") vì Swift gộp "\r\n" thành 1 Character (grapheme cluster) duy nhất - tách theo Character sẽ
    /// không bao giờ khớp được "\n" khi input dùng xuống dòng kiểu CRLF.
    func feed(chunk: String) -> [SuKienSSE] {
        bufferBytes.append(contentsOf: chunk.utf8)
        var ketQua: [SuKienSSE] = []
        while let i = bufferBytes.firstIndex(of: 0x0A) {
            var dongBytes = Array(bufferBytes[..<i])
            bufferBytes.removeFirst(i + 1)
            if dongBytes.last == 0x0D { dongBytes.removeLast() }
            let s = String(decoding: dongBytes, as: UTF8.self)
            if let sk = feed(line: s) { ketQua.append(sk) }
        }
        return ketQua
    }

    private var bufferBytes: [UInt8] = []

    private func resetKhoi() {
        loaiDangGom = "message"
        dongData = []
        idDangGom = nil
    }

    private func tachTruong(_ line: String) -> (String, String) {
        guard let i = line.firstIndex(of: ":") else { return (line, "") }
        let truong = String(line[line.startIndex..<i])
        var giaTri = String(line[line.index(after: i)...])
        if giaTri.hasPrefix(" ") { giaTri.removeFirst() }
        return (truong, giaTri)
    }
}
