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

    /// Nạp 1 khối dữ liệu thô (có thể chứa nhiều dòng, cắt ở ranh giới bất kỳ) -> trả về các sự kiện hoàn chỉnh theo thứ tự.
    func feed(chunk: String) -> [SuKienSSE] {
        var ketQua: [SuKienSSE] = []
        var phanConLai = bufferConLai + chunk
        var dong: [Substring] = []
        // tach theo \n, giu lai phan cuoi chua co \n ket thuc de nap tiep lan sau
        if phanConLai.hasSuffix("\n") {
            dong = phanConLai.dropLast().split(separator: "\n", omittingEmptySubsequences: false)
            bufferConLai = ""
        } else {
            let tatCa = phanConLai.split(separator: "\n", omittingEmptySubsequences: false)
            dong = Array(tatCa.dropLast())
            bufferConLai = String(tatCa.last ?? "")
        }
        for d in dong {
            var s = String(d)
            if s.hasSuffix("\r") { s.removeLast() }
            if let sk = feed(line: s) { ketQua.append(sk) }
        }
        phanConLai = ""
        return ketQua
    }

    private var bufferConLai = ""

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
