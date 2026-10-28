//
//  CloudflareAccessTests.swift
//  ZaloAppTests
//
//  Kiem thu helper CloudflareAccess.
//

import XCTest
@testable import ZaloLuuTru

final class CloudflareAccessTests: XCTestCase {

    override func tearDown() {
        CloudflareAccess.clear()
        super.tearDown()
    }

    // MARK: - JWT Expiry Tests

    func testJwtExpiry_TuTaoJWTGia() {
        // {"alg":"none"}.{"exp":1893456000,"sub":"test"}.sig
        // Header: eyJhbGciOiJub25lIn0
        // Payload: eyJleHAiOjE4OTM0NTYwMDAsInN1YiI6InRlc3QifQ
        let fakeJWT = "eyJhbGciOiJub25lIn0.eyJleHAiOjE4OTM0NTYwMDAsInN1YiI6InRlc3QifQ.sig"
        let exp = CloudflareAccess.jwtExpiry(fakeJWT)

        XCTAssertEqual(exp, Date(timeIntervalSince1970: 1893456000))
    }

    func testJwtExpiry_PayloadCoKyTuCongVaXuyetSauBase64() {
        // Payload {"exp":1893456000,"x":">>?"} ma hoa base64url chua '-' va '_'
        // Khi convert sang base64 se tro thanh '+' va '/' (co ky tu +/ sau base64)
        // eyJleHAiOjE4OTM0NTYwMDAsIngiOiI-Pj8_In0 -> eyJleHAiOjE4OTM0NTYwMDAsIngiOiI+Pj8/In0
        let jwtBase64Url = "eyJhbGciOiJub25lIn0.eyJleHAiOjE4OTM0NTYwMDAsIngiOiI-Pj8_In0.sig"
        let exp1 = CloudflareAccess.jwtExpiry(jwtBase64Url)
        XCTAssertEqual(exp1, Date(timeIntervalSince1970: 1893456000))

        // Truong hop payload truc tiep mang ky tu '+' va '/' trong base64
        let jwtStandardBase64 = "eyJhbGciOiJub25lIn0.eyJleHAiOjE4OTM0NTYwMDAsIngiOiI+Pj8/In0.sig"
        let exp2 = CloudflareAccess.jwtExpiry(jwtStandardBase64)
        XCTAssertEqual(exp2, Date(timeIntervalSince1970: 1893456000))
    }

    func testJwtExpiry_ChuoiRacTraVeNil() {
        XCTAssertNil(CloudflareAccess.jwtExpiry("abc"))
        XCTAssertNil(CloudflareAccess.jwtExpiry("a.b.c"))
        XCTAssertNil(CloudflareAccess.jwtExpiry(""))
    }

    // MARK: - Apply Tests

    func testApplyTo_GhepVoiCookieSanCo() {
        defer {
            CloudflareAccess.clear()
        }

        let fakeCookie = "cf_fake_cookie_test_value"
        CloudflareAccess.save(fakeCookie)

        var request = URLRequest(url: URL(string: "https://example.com/api")!)
        request.setValue("zw=abc", forHTTPHeaderField: "Cookie")

        CloudflareAccess.apply(to: &request)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "zw=abc; CF_Authorization=\(fakeCookie)")
        XCTAssertFalse(request.httpShouldHandleCookies)
    }

    func testApplyTo_ChuaCoCookieHeader() {
        defer {
            CloudflareAccess.clear()
        }

        let fakeCookie = "cf_fake_cookie_test_value"
        CloudflareAccess.save(fakeCookie)

        var request = URLRequest(url: URL(string: "https://example.com/api")!)
        CloudflareAccess.apply(to: &request)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "CF_Authorization=\(fakeCookie)")
        XCTAssertFalse(request.httpShouldHandleCookies)
    }

    func testApplyTo_KhiChuaLuuCookie_KhongThayDoiRequest() {
        CloudflareAccess.clear()

        var request = URLRequest(url: URL(string: "https://example.com/api")!)
        request.setValue("zw=abc", forHTTPHeaderField: "Cookie")

        CloudflareAccess.apply(to: &request)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "zw=abc")
        XCTAssertTrue(request.httpShouldHandleCookies)
    }

    // MARK: - Helper Tests

    func testIsAccessURL() {
        XCTAssertTrue(CloudflareAccess.isAccessURL(URL(string: "https://myteam.cloudflareaccess.com/login")))
        XCTAssertFalse(CloudflareAccess.isAccessURL(URL(string: "https://example.com/api")))
        XCTAssertFalse(CloudflareAccess.isAccessURL(nil))
    }

    func testDomainMatches() {
        XCTAssertTrue(CloudflareAccess.domainMatches(cookieDomain: "example.com", host: "example.com"))
        XCTAssertTrue(CloudflareAccess.domainMatches(cookieDomain: ".example.com", host: "example.com"))
        XCTAssertTrue(CloudflareAccess.domainMatches(cookieDomain: "example.com", host: "sub.example.com"))
        XCTAssertTrue(CloudflareAccess.domainMatches(cookieDomain: ".example.com", host: "sub.example.com"))
        XCTAssertFalse(CloudflareAccess.domainMatches(cookieDomain: "example.com", host: "otherdomain.com"))
    }
}
