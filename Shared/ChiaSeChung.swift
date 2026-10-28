// v5.4: dữ liệu dùng chung giữa app và tiện ích Chia sẻ (ZaloShare) qua App Group,
// + "gợi ý người nhận" trên bảng Chia sẻ của iOS (INSendMessageIntent, giống Zalo gốc).
// Dùng chung 1 file cho cả 2 target (project.yml: sources Shared).

import Foundation
import Intents

struct NguoiNhanChiaSe: Codable, Hashable, Identifiable {
    let id: String        // mã cuộc trò chuyện (cuoc.id)
    let ten: String
    let laNhom: Bool
}

enum ChiaSeChung {
    /// ESign ký bằng chứng chỉ có các App Group này -> lấy nhóm đầu tiên máy cho truy cập.
    static let cacAppGroup = [
        "group.5c828fdde559161e.1", "group.5c828fdde559161e.2", "group.5c828fdde559161e.3",
        "group.5c828fdde559161e.4", "group.5c828fdde559161e.5", "group.app.guava948.kale5858",
    ]

    static let appGroup: String? = cacAppGroup.first {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
    }

    static var thuMucChung: URL? {
        appGroup.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }

    private static var kho: UserDefaults? { appGroup.flatMap { UserDefaults(suiteName: $0) } }
    private static let khoaDiaChi = "cs_dia_chi_may_chu"
    private static let khoaPhien = "cs_phien_zw"
    private static let khoaCF = "cs_cf_authorization"
    private static let khoaNguoiNhan = "cs_ds_nguoi_nhan"

    // ---------------------------------------------------------------- app ghi, tiện ích đọc
    static func luu(diaChi: String, phien: String?, dsNguoiNhan: [NguoiNhanChiaSe]) {
        guard let kho else { return }
        kho.set(diaChi, forKey: khoaDiaChi)
        if let phien, !phien.isEmpty { kho.set(phien, forKey: khoaPhien) }
        if let data = try? JSONEncoder().encode(dsNguoiNhan) { kho.set(data, forKey: khoaNguoiNhan) }
    }

    static func luuCF(_ s: String?) {
        guard let kho else { return }
        if let s, !s.isEmpty {
            kho.set(s, forKey: khoaCF)
        } else {
            kho.removeObject(forKey: khoaCF)
        }
    }

    static func xoaPhien() { kho?.removeObject(forKey: khoaPhien) }

    static var diaChi: String? { kho?.string(forKey: khoaDiaChi) }
    static var phien: String? { kho?.string(forKey: khoaPhien) }
    static var cf: String? { kho?.string(forKey: khoaCF) }
    static var dsNguoiNhan: [NguoiNhanChiaSe] {
        guard let data = kho?.data(forKey: khoaNguoiNhan) else { return [] }
        return (try? JSONDecoder().decode([NguoiNhanChiaSe].self, from: data)) ?? []
    }

    // ---------------------------------------------------------------- gợi ý trên bảng Chia sẻ
    static func taoIntent(_ n: NguoiNhanChiaSe) -> INSendMessageIntent {
        let nguoi = INPerson(personHandle: INPersonHandle(value: n.id, type: .unknown), nameComponents: nil,
                             displayName: n.ten, image: nil, contactIdentifier: nil, customIdentifier: n.id)
        let intent = INSendMessageIntent(recipients: n.laNhom ? nil : [nguoi], outgoingMessageType: .outgoingMessageText,
                                         content: nil, speakableGroupName: n.laNhom ? INSpeakableString(spokenPhrase: n.ten) : nil,
                                         conversationIdentifier: n.id, serviceName: nil, sender: nil, attachments: nil)
        return intent
    }

    /// Báo iOS "vừa nhắn cho người/nhóm này" -> hiện thành gợi ý hàng đầu bảng Chia sẻ.
    static func baoDaNhan(_ n: NguoiNhanChiaSe) {
        let tt = INInteraction(intent: taoIntent(n), response: nil)
        tt.direction = .outgoing
        tt.groupIdentifier = n.id
        tt.donate { _ in }
    }
}
