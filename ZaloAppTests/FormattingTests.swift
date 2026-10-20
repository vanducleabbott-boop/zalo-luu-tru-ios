import XCTest
@testable import ZaloLuuTru

final class FormattingTests: XCTestCase {
    private func tinMau(id: String, uid: String?, laToi: Bool, ts: Int64, kieu: String = "chu") -> Tin {
        Tin(msgId: id, cliMsgId: id, cuocId: "c1", uid: uid, tenNguoi: uid, laToi: laToi, ts: ts,
            loai: nil, kieu: kieu, chu: "nd", url: nil, file: nil, tenFile: nil, kichThuoc: nil,
            quote: nil, thuHoi: false, phu: nil, camXuc: [])
    }

    // ---------------------------------------------------------------- gộp theo người/ngày (GomNhom)
    func testCungNhom_CungNguoiTrongVong5Phut() {
        let a = tinMau(id: "1", uid: "u1", laToi: false, ts: 1_000_000)
        let b = tinMau(id: "2", uid: "u1", laToi: false, ts: 1_000_000 + 4 * 60_000)
        XCTAssertTrue(GomNhom.cungNhom(hienTai: b, truoc: a))
    }

    func testCungNhom_QuaCachNhauTrenNguongThiKhongGop() {
        let a = tinMau(id: "1", uid: "u1", laToi: false, ts: 1_000_000)
        let b = tinMau(id: "2", uid: "u1", laToi: false, ts: 1_000_000 + 6 * 60_000)
        XCTAssertFalse(GomNhom.cungNhom(hienTai: b, truoc: a))
    }

    func testCungNhom_KhacNguoiThiKhongGop() {
        let a = tinMau(id: "1", uid: "u1", laToi: false, ts: 1_000_000)
        let b = tinMau(id: "2", uid: "u2", laToi: false, ts: 1_000_010)
        XCTAssertFalse(GomNhom.cungNhom(hienTai: b, truoc: a))
    }

    func testGomTheoNgay_ChenMocNgayKhiDoiNgay() {
        let ngayMot: Int64 = 1_700_000_000_000          // moc tuy y
        let ngayHai: Int64 = ngayMot + 36 * 60 * 60_000  // +36h chac chan sang ngay khac
        let ds = [tinMau(id: "1", uid: "u1", laToi: false, ts: ngayMot),
                  tinMau(id: "2", uid: "u1", laToi: false, ts: ngayHai)]
        let muc = GomNhom.gomTheoNgay(ds)
        // phai co 2 moc ngay (1 truoc tin dau, 1 truoc tin thu 2) xen giua 2 tin
        let soMocNgay = muc.filter { if case .ngay = $0 { return true }; return false }.count
        XCTAssertEqual(soMocNgay, 2)
        XCTAssertEqual(muc.count, 4)   // ngay, tin, ngay, tin
    }

    func testGomTheoNgay_DoiNgayLuonBatDauNhomMoiDuCungNguoi() {
        let ngayMot: Int64 = 1_700_000_000_000
        let ngayHai: Int64 = ngayMot + 36 * 60 * 60_000
        let ds = [tinMau(id: "1", uid: "u1", laToi: false, ts: ngayMot),
                  tinMau(id: "2", uid: "u1", laToi: false, ts: ngayHai)]
        let muc = GomNhom.gomTheoNgay(ds)
        guard case .tin(_, let dauNhom2, _) = muc[3] else { return XCTFail() }
        XCTAssertTrue(dauNhom2, "sang ngay moi phai la dau 1 nhom moi du cung nguoi gui")
    }

    // ---------------------------------------------------------------- album (v4.3): nhiều ảnh gửi 1 lần -> 1 khung lưới
    private func anhAlbum(id: String, uid: String = "u1", ts: Int64, album: String?, i: Int = 0, n: Int = 3) -> Tin {
        Tin(msgId: id, cliMsgId: id, cuocId: "c1", uid: uid, tenNguoi: uid, laToi: false, ts: ts,
            loai: nil, kieu: "anh", chu: "", url: nil, file: "media/x/\(id).jpg", tenFile: nil, kichThuoc: nil,
            quote: nil, thuHoi: false,
            phu: album.map { Phu(khung: nil, ms: nil, lich: nil, tag: nil, cuocNguon: nil, album: AlbumInfo(id: $0, i: i, n: n)) },
            camXuc: [])
    }

    func testAlbum_GopTinCungAlbumThanh1MucVaSapTheoThuTu() {
        let t0: Int64 = 1_700_000_000_000
        // Zalo bao ve KHONG theo thu tu i (do that 20/10: 1,2,5,6,3,4...) -> phai sap lai theo i
        let ds = [anhAlbum(id: "b", ts: t0, album: "A", i: 1), anhAlbum(id: "a", ts: t0 + 1, album: "A", i: 0),
                  anhAlbum(id: "c", ts: t0 + 2, album: "A", i: 2)]
        let muc = GomNhom.gomTheoNgay(ds)
        XCTAssertEqual(muc.count, 2)   // ngay + 1 album
        guard case .album(let tin, _, let cuoi) = muc[1] else { return XCTFail("phai la .album") }
        XCTAssertEqual(tin.map(\.msgId), ["a", "b", "c"])
        XCTAssertTrue(cuoi)
    }

    func testAlbum_KhacAlbumHoacKhacNguoiThiTach() {
        let t0: Int64 = 1_700_000_000_000
        let ds = [anhAlbum(id: "1", ts: t0, album: "A"), anhAlbum(id: "2", ts: t0 + 1, album: "A"),
                  anhAlbum(id: "3", ts: t0 + 2, album: "B"), anhAlbum(id: "4", ts: t0 + 3, album: "B"),
                  anhAlbum(id: "5", uid: "u2", ts: t0 + 4, album: "B"),
                  anhAlbum(id: "6", ts: t0 + 5, album: nil)]
        let muc = GomNhom.gomTheoNgay(ds).filter { if case .ngay = $0 { return false }; return true }
        XCTAssertEqual(muc.count, 4)   // album A(2) + album B(2) + tin u2 + tin khong album
        if case .album(let a, _, _) = muc[0] { XCTAssertEqual(a.count, 2) } else { XCTFail() }
        if case .album(let b, _, _) = muc[1] { XCTAssertEqual(b.count, 2) } else { XCTFail() }
        if case .tin = muc[2] {} else { XCTFail("album 1 anh cua nguoi khac la tin thuong") }
        if case .tin = muc[3] {} else { XCTFail() }
    }

    func testAlbum_ChiaHangKhongCoHang1AnhLe() {
        XCTAssertEqual(AlbumLuoiView.chiaHang(2), [2])
        XCTAssertEqual(AlbumLuoiView.chiaHang(3), [3])
        XCTAssertEqual(AlbumLuoiView.chiaHang(4), [2, 2])
        XCTAssertEqual(AlbumLuoiView.chiaHang(5), [3, 2])
        XCTAssertEqual(AlbumLuoiView.chiaHang(7), [3, 2, 2])
        for n in 2...30 {
            let h = AlbumLuoiView.chiaHang(n)
            XCTAssertEqual(h.reduce(0, +), n, "n=\(n)")
            XCTAssertFalse(h.contains(1), "n=\(n) khong duoc co hang 1 anh: \(h)")
        }
    }

    // ---------------------------------------------------------------- ghép tin realtime + phân trang (PhanTrang)
    func testGanTin_TinMoiDuocChenDungThuTu() {
        var ds = [tinMau(id: "1", uid: "u1", laToi: false, ts: 100), tinMau(id: "3", uid: "u1", laToi: false, ts: 300)]
        ds = PhanTrang.ganTin(ds, tinMau(id: "2", uid: "u1", laToi: false, ts: 200))
        XCTAssertEqual(ds.map(\.msgId), ["1", "2", "3"])
    }

    func testGanTin_TinDaCoThiThayTheKhongNhanBan() {
        var ds = [tinMau(id: "1", uid: "u1", laToi: false, ts: 100)]
        let suaLai = tinMau(id: "1", uid: "u1", laToi: false, ts: 100, kieu: "chu")
        ds = PhanTrang.ganTin(ds, suaLai)
        XCTAssertEqual(ds.count, 1)
    }

    func testNoiTrangCu_HetTinKhiTrangCuIt() {
        let hienTai = [tinMau(id: "60", uid: "u1", laToi: false, ts: 6000)]
        let trangCu = (1...10).map { tinMau(id: "\($0)", uid: "u1", laToi: false, ts: Int64($0) * 10) }
        let (ds, het) = PhanTrang.noiTrangCu(hienTai: hienTai, trangCu: trangCu)
        XCTAssertEqual(ds.count, 11)
        XCTAssertEqual(ds.first?.msgId, "1")
        XCTAssertTrue(het, "trang cu < 60 tin -> da toi tin cu nhat")
    }

    func testNoiTrangCu_ChuaHetKhiTrangCuDuNguong() {
        let trangCu = (1...60).map { tinMau(id: "\($0)", uid: "u1", laToi: false, ts: Int64($0)) }
        let (_, het) = PhanTrang.noiTrangCu(hienTai: [], trangCu: trangCu)
        XCTAssertFalse(het)
    }

    // ---------------------------------------------------------------- tách "@Tag" theo vị trí UTF-16 (DinhDangChu)
    func testPhanDoanTag_KhongCoTagTraNguyenVan() {
        let doan = DinhDangChu.phanDoanTag("xin chao", tags: nil)
        XCTAssertEqual(doan.count, 1)
        XCTAssertEqual(doan[0].text, "xin chao")
        XCTAssertFalse(doan[0].laTag)
    }

    func testPhanDoanTag_MotTagODauCau() {
        let chu = "@Minh Hoa ok em nhé"
        let doan = DinhDangChu.phanDoanTag(chu, tags: [TagMark(uid: "u1", pos: 0, len: 9)])
        XCTAssertEqual(doan.map(\.text), ["@Minh Hoa", " ok em nhé"])
        XCTAssertEqual(doan.map(\.laTag), [true, false])
    }

    func testPhanDoanTag_TagOGiua() {
        // Tinh pos/len tu chinh chuoi (UTF-16, giong cach Zalo/JS tinh) de khong phu thuoc dang NFC/NFD cua "ờ".
        let truoc = "nhờ ", nhanTag = "@An", sau = " xem giúp"
        let chu = truoc + nhanTag + sau
        let doan = DinhDangChu.phanDoanTag(chu, tags: [TagMark(uid: "u1", pos: truoc.utf16.count, len: nhanTag.utf16.count)])
        XCTAssertEqual(doan.map(\.text), [truoc, nhanTag, sau])
        XCTAssertEqual(doan.map(\.laTag), [false, true, false])
    }

    func testPhanDoanTag_ViTriKhongHopLeBiBoQua() {
        let doan = DinhDangChu.phanDoanTag("ngan", tags: [TagMark(uid: "u1", pos: 100, len: 3)])
        XCTAssertEqual(doan.count, 1)
        XCTAssertFalse(doan[0].laTag)
    }

    // ---------------------------------------------------------------- định dạng ngày/giờ/dung lượng
    func testKichCo() {
        XCTAssertEqual(DinhDang.kichCo(500), "1 KB")
        XCTAssertEqual(DinhDang.kichCo(2_097_152), "2.0 MB")
        XCTAssertEqual(DinhDang.kichCo(nil), "")
    }

    func testGioNgan_HomNayLaGioPhut() {
        // Neo vao giua trua de "-1 phut" khong bao gio vuot qua ranh gioi ngay, bat ke mui gio may chay test.
        let bayGio = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let ts = Int64(bayGio.timeIntervalSince1970 * 1000) - 60_000
        let s = DinhDang.gioNgan(ts, bayGio: bayGio)
        XCTAssertTrue(s.contains(":"))
    }

    func testGioNgan_HomQua() {
        let bayGio = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let homQua = Calendar.current.date(byAdding: .day, value: -1, to: bayGio)!
        let s = DinhDang.gioNgan(Int64(homQua.timeIntervalSince1970 * 1000), bayGio: bayGio)
        XCTAssertEqual(s, "Hôm qua")
    }

    func testDuoiFile_VaTenHienThiFile() {
        // Kiểm tra nhận diện phần mở rộng Word, Excel, PowerPoint chuẩn xác (cả khi có hậu tố .tai)
        XCTAssertEqual(DinhDang.duoiFile("bao_cao.docx"), "docx")
        XCTAssertEqual(DinhDang.duoiFile("bang_tinh.xlsx"), "xlsx")
        XCTAssertEqual(DinhDang.duoiFile("thuyet_trinh.pptx"), "pptx")
        XCTAssertEqual(DinhDang.duoiFile("tai_lieu.pdf"), "pdf")
        XCTAssertEqual(DinhDang.duoiFile("thuyet_trinh.pptx.tai"), "pptx")
        XCTAssertEqual(DinhDang.duoiFile("word_doc.docx.tai"), "docx")

        // Tên hiển thị sạch
        XCTAssertEqual(DinhDang.tenHienThiFile("bao_cao.docx.tai"), "bao_cao.docx")
        XCTAssertEqual(DinhDang.tenHienThiFile("thuyet_trinh.pptx"), "thuyet_trinh.pptx")
    }
}
