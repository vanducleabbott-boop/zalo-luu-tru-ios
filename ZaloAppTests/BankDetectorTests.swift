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

    func testTheNganHangZalo_MayChuDaGiaiMa_HienChuyenKhoan() {
        func the(_ chu: String) -> Tin {
            Tin(msgId: "1", cliMsgId: "1", cuocId: "c", uid: "u", tenNguoi: nil, laToi: false, ts: 0,
                loai: "chat.webcontent", kieu: "chu", chu: chu, url: nil, file: nil, tenFile: nil, kichThuoc: nil,
                quote: nil, thuHoi: false, phu: nil, camXuc: [])
        }
        let daGiai = the("VPBank - 0912345678")
        XCTAssertNil(daGiai.loaiDacBiet)
        XCTAssertEqual(daGiai.thongTinChuyenKhoan?.stk, "0912345678")
        XCTAssertEqual(the("[Loại tin chưa hỗ trợ: chat.webcontent]").loaiDacBiet, .theZalo)
    }
}
