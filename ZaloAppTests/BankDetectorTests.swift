import XCTest
@testable import ZaloLuuTru

final class BankDetectorTests: XCTestCase {
    func testTenNganHangVietTach_SoTrenVaHoTen() {
        let ck = BankDetector.parse(text: "VP bank.  0912345678 Nguyễn Văn An")
        XCTAssertEqual(ck?.maNganHang, "vpbank")
        XCTAssertEqual(ck?.stk, "0912345678")
        XCTAssertEqual(ck?.tenNguoiNhan, "Nguyễn Văn An")
    }

    func testTuKhoaNgan_KhongNhanNhamSoDienThoai() {
        XCTAssertNil(BankDetector.parse(text: "mb gọi lại 0912345678 nhé"))
    }

    func testCoChuStk() {
        let ck = BankDetector.parse(text: "BIDV stk 1234567890")
        XCTAssertEqual(ck?.maNganHang, "bidv")
        XCTAssertEqual(ck?.stk, "1234567890")
    }
}
