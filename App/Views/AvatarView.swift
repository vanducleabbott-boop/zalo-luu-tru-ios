// Khớp ava()/chuCai()/maMau() trong web/index.html: không có ảnh -> chữ cái đầu trên nền màu theo khoá.

import SwiftUI

enum AvatarMau {
    static let bang: [Color] = [
        Color(red: 0.37, green: 0.55, blue: 0.91), Color(red: 0.91, green: 0.57, blue: 0.37),
        Color(red: 0.37, green: 0.72, blue: 0.55), Color(red: 0.69, green: 0.44, blue: 0.84),
        Color(red: 0.91, green: 0.44, blue: 0.54), Color(red: 0.31, green: 0.70, blue: 0.77),
        Color(red: 0.79, green: 0.64, blue: 0.23), Color(red: 0.49, green: 0.55, blue: 0.88),
    ]
    static func mau(_ khoa: String) -> Color {
        var h: UInt32 = 0
        for b in khoa.utf8 { h = h &* 31 &+ UInt32(b) }
        return bang[Int(h % UInt32(bang.count))]
    }
    static func chuCai(_ ten: String) -> String {
        let tu = ten.trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard !tu.isEmpty else { return "?" }
        let cuoi = tu.last.flatMap { $0.first }.map(String.init) ?? "?"
        let ketQua = tu.count > 1 ? (tu[tu.count - 2].first.map(String.init) ?? "") + cuoi : cuoi
        return ketQua.uppercased()
    }
}

struct AvatarView: View {
    let ten: String
    let anh: String?
    let khoa: String
    var kichThuoc: CGFloat = 44

    var body: some View {
        Group {
            if khoa == "so-tay" {
                Text("📒").font(.system(size: kichThuoc * 0.55))
                    .frame(width: kichThuoc, height: kichThuoc)
                    .background(Color(red: 0.96, green: 0.65, blue: 0.14), in: Circle())
            } else if let anh, let u = URL(string: anh), !anh.isEmpty {
                AsyncImage(url: u) { pha in
                    switch pha {
                    case .success(let img): img.resizable().scaledToFill()
                    default: chuNen
                    }
                }
                .frame(width: kichThuoc, height: kichThuoc)
                .clipShape(Circle())
            } else {
                chuNen
            }
        }
    }

    private var chuNen: some View {
        Text(AvatarMau.chuCai(ten))
            .font(.system(size: kichThuoc * 0.38, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: kichThuoc, height: kichThuoc)
            .background(AvatarMau.mau(khoa), in: Circle())
    }
}
