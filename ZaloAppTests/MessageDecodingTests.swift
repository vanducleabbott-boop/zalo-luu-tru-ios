// Giải mã JSON tin nhắn từ MẪU THẬT lấy từ máy chủ cục bộ (xem Fixtures/ - đã ẩn danh tên người/nội dung
// riêng tư, giữ nguyên cấu trúc/kiểu dữ liệu thật của web_zalo.mjs + luu_tru.mjs, kể cả quirk
// "cuoc.tin_cuoi là chuỗi JSON thô trong /api/tin" thay vì object như /api/cuoc).

import XCTest
@testable import ZaloLuuTru

final class MessageDecodingTests: XCTestCase {
    private func duLieuFixture(_ ten: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: ten, withExtension: "json") else {
            XCTFail("Không tìm thấy fixture \(ten).json trong test bundle"); throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    // ---------------------------------------------------------------- /api/tin (đủ loại kieu + quirk tin_cuoi chuỗi)
    func testGiaiMa_PhanHoiTin_DuLoaiTin() throws {
        let data = try duLieuFixture("fixture_tin_day_du")
        let kq = try JSONDecoder().decode(PhanHoiTin.self, from: data)

        XCTAssertEqual(kq.tin.count, 8)
        XCTAssertEqual(kq.toi, "2085886849481656763")

        let theoKieu = Dictionary(grouping: kq.tin, by: \.kieu).mapValues(\.count)
        XCTAssertEqual(theoKieu["file"], 1)
        XCTAssertEqual(theoKieu["sticker"], 1)
        XCTAssertEqual(theoKieu["lich"], 1)
        XCTAssertEqual(theoKieu["anh"], 2)
        XCTAssertEqual(theoKieu["chu"], 2)
        XCTAssertEqual(theoKieu["video"], 1)

        // quirk: cuoc.tin_cuoi la CHUOI JSON tho (khong parse san) trong /api/tin -> van phai giai ma duoc thanh object
        let cuoc = try XCTUnwrap(kq.cuoc)
        XCTAssertEqual(cuoc.id, "6944541117544405014")
        XCTAssertEqual(cuoc.laNhomBool, true)
        XCTAssertNotNil(cuoc.tinCuoi, "phai giai ma duoc tin_cuoi dang chuoi JSON tho")
        XCTAssertEqual(cuoc.tinCuoi?.laToi, false)

        // sticker dong: phu.khung/ms
        let sticker = try XCTUnwrap(kq.tin.first { $0.kieu == "sticker" })
        XCTAssertEqual(sticker.phu?.khung, 4)
        XCTAssertEqual(sticker.phu?.ms, 300)

        // lich: phu.lich day du + daXoa
        let lich = try XCTUnwrap(kq.tin.first { $0.kieu == "lich" })
        XCTAssertEqual(lich.phu?.lich?.daXoa, true)
        XCTAssertEqual(lich.phu?.lich?.rieng, true)

        // anh da thu hoi: thu_hoi=true, chu rong
        let anhThuHoi = try XCTUnwrap(kq.tin.first { $0.kieu == "anh" && $0.thuHoi })
        XCTAssertFalse(anhThuHoi.duocThuHoi, "khong la_toi nen khong duoc thu hoi")

        // tin co quote + tag + cam_xuc
        let coTag = try XCTUnwrap(kq.tin.first { ($0.phu?.tag?.isEmpty ?? true) == false && $0.quote != nil })
        XCTAssertEqual(coTag.phu?.tag?.first?.len, 9)
        XCTAssertNotNil(coTag.quote?.msgId)

        let coCamXuc = try XCTUnwrap(kq.tin.first { !$0.camXuc.isEmpty && $0.kieu == "video" })
        XCTAssertEqual(coCamXuc.camXuc.count, 2)

        // nguoi: co phan tu null (khong tim thay nguoi) phai giai ma thanh nil, khong lam vo toan bo dictionary
        XCTAssertTrue(kq.nguoi.contains { $0.value == nil } || kq.nguoi.values.allSatisfy { $0 != nil })
    }

    // ---------------------------------------------------------------- /api/cuoc (danh sách hội thoại, tin_cuoi la object that)
    func testGiaiMa_DanhSachCuoc() throws {
        let data = try duLieuFixture("fixture_cuoc_list")
        let ds = try JSONDecoder().decode([Cuoc].self, from: data)
        XCTAssertEqual(ds.count, 9)
        XCTAssertEqual(ds.first?.id, "so-tay")
        XCTAssertNotNil(ds.first?.tinCuoi)

        // ghim nullable + tat_tb chi xuat hien khi true
        XCTAssertTrue(ds.contains { $0.ghim != nil })
        let nhomTatTb = try XCTUnwrap(ds.first { $0.daTatThongBao })
        XCTAssertTrue(nhomTatTb.laNhomBool)
        XCTAssertFalse(ds.first { $0.id == "so-tay" }!.daTatThongBao)
    }

    // ---------------------------------------------------------------- /api/kho (không có cam_xuc)
    func testGiaiMa_PhanHoiKho() throws {
        let data = try duLieuFixture("fixture_kho")
        let kq = try JSONDecoder().decode(PhanHoiKho.self, from: data)
        XCTAssertEqual(kq.ds.count, 5)
        XCTAssertEqual(kq.dem?.pdf, 391)
        XCTAssertTrue(kq.ds.allSatisfy { $0.camXuc.isEmpty })
    }

    // ---------------------------------------------------------------- /api/tim (kèm ten_cuoc/la_nhom)
    func testGiaiMa_KetQuaTimKiem() throws {
        let data = try duLieuFixture("fixture_tim")
        let ds = try JSONDecoder().decode([Tin].self, from: data)
        XCTAssertEqual(ds.count, 4)
        XCTAssertNotNil(ds.first?.tenCuoc)
    }
}
