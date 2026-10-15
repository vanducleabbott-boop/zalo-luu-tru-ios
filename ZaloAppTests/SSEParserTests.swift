import XCTest
@testable import ZaloLuuTru

final class SSEParserTests: XCTestCase {
    func testSuKienDonGian() {
        let p = SSEParser()
        XCTAssertNil(p.feed(line: "event: tin"))
        XCTAssertNil(p.feed(line: "data: {\"cuoc_id\":\"abc\"}"))
        let sk = p.feed(line: "")
        XCTAssertEqual(sk?.loai, "tin")
        XCTAssertEqual(sk?.data, "{\"cuoc_id\":\"abc\"}")
    }

    func testNhieuDongData_NoiBangXuongDong() {
        let p = SSEParser()
        _ = p.feed(line: "event: sua")
        _ = p.feed(line: "data: dong-1")
        _ = p.feed(line: "data: dong-2")
        let sk = p.feed(line: "")
        XCTAssertEqual(sk?.data, "dong-1\ndong-2")
    }

    func testKhongCoDongEvent_MacDinhLaMessage() {
        let p = SSEParser()
        _ = p.feed(line: "data: xyz")
        let sk = p.feed(line: "")
        XCTAssertEqual(sk?.loai, "message")
    }

    func testDongTrongLienTiep_KhongTraSuKienRong() {
        let p = SSEParser()
        XCTAssertNil(p.feed(line: ""))
        XCTAssertNil(p.feed(line: ""))
    }

    func testDongComment_BiBoQua() {
        let p = SSEParser()
        XCTAssertNil(p.feed(line: ": nhip giu ket noi"))
        _ = p.feed(line: "event: nhip")
        _ = p.feed(line: "data: {}")
        let sk = p.feed(line: "")
        XCTAssertEqual(sk?.loai, "nhip")
    }

    func testRetry() {
        let p = SSEParser()
        _ = p.feed(line: "retry: 3000")
        XCTAssertEqual(p.retryMs, 3000)
    }

    /// Mô phỏng đúng cách máy chủ phát: "retry: 3000\n\n" rồi nhiều sự kiện "event:...\ndata:...\n\n"
    func testChuoiThatTuMayChu_NhieuSuKienLienTiep() {
        let p = SSEParser()
        let raw = "retry: 3000\n\nevent: tin\ndata: {\"a\":1}\n\nevent: nhip\ndata: {}\n\n"
        let suKien = p.feed(chunk: raw)
        guard suKien.count == 2 else { return XCTFail("Mong đợi 2 sự kiện, được \(suKien.count)") }
        XCTAssertEqual(suKien[0].loai, "tin")
        XCTAssertEqual(suKien[0].data, "{\"a\":1}")
        XCTAssertEqual(suKien[1].loai, "nhip")
    }

    /// Dữ liệu tới theo từng mảnh byte nhỏ (chẻ ngang 1 dòng) - vẫn phải ghép đúng.
    func testChePhanManh_CatNgangGiuaDong() {
        let p = SSEParser()
        var tatCa: [SuKienSSE] = []
        let raw = "event: tin\ndata: {\"cuoc_id\":\"6944541117544405014\",\"tin\":{}}\n\n"
        // chia raw thanh cac manh 7 ky tu de mo phong doc byte-by-byte tu mang
        var i = raw.startIndex
        while i < raw.endIndex {
            let ke = raw.index(i, offsetBy: 7, limitedBy: raw.endIndex) ?? raw.endIndex
            tatCa.append(contentsOf: p.feed(chunk: String(raw[i..<ke])))
            i = ke
        }
        guard tatCa.count == 1 else { return XCTFail("Mong đợi 1 sự kiện, được \(tatCa.count)") }
        XCTAssertEqual(tatCa[0].loai, "tin")
        XCTAssertTrue(tatCa[0].data.contains("6944541117544405014"))
    }

    func testXuongDongKieuCRLF_VanGhepDungSuKien() {
        let p = SSEParser()
        let suKien = p.feed(chunk: "event: doc\r\ndata: {\"cuoc_id\":\"x\"}\r\n\r\n")
        guard suKien.count == 1 else { return XCTFail("Mong đợi 1 sự kiện, được \(suKien.count)") }
        XCTAssertEqual(suKien[0].loai, "doc")
        XCTAssertEqual(suKien[0].data, "{\"cuoc_id\":\"x\"}")   // \r phai duoc cat, khong con lan trong data
    }

    // ---------------------------------------------------------------- hàm quyết định nối lại (không mạng)
    func testCanReconnect_ImLangQuaNguong() {
        let bayGio = Date()
        XCTAssertTrue(canReconnectSSE(lastHeard: bayGio.addingTimeInterval(-41), now: bayGio))
        XCTAssertFalse(canReconnectSSE(lastHeard: bayGio.addingTimeInterval(-10), now: bayGio))
    }
}
