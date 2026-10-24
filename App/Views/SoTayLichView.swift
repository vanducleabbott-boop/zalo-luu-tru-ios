// v5.9: Sổ tay dạng LỊCH THÁNG - mỗi ngày chấm số lịch hẹn, bấm 1 ngày xem các lịch hẹn của ngày đó,
// bấm 1 lịch hẹn -> mở đúng cuộc trò chuyện và nhảy tới tin nhắn đã tạo lịch hẹn đó.
// Nguồn dữ liệu: các tin kieu == "lich" trong cuộc Sổ tay (tải hết các trang + cập nhật realtime qua ChatViewModel).

import SwiftUI

/// 1 lần diễn ra của 1 lịch hẹn trong 1 ngày (lịch lặp ngày/tuần/tháng có nhiều lần).
private struct LanHen: Identifiable {
    let tin: Tin
    let lich: LichHen
    let luc: Date
    var id: String { (lich.id ?? tin.msgId) + "_\(Int(luc.timeIntervalSince1970))" }
}

struct SoTayLichView: View {
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject var vm: ChatViewModel
    /// Lịch tạo ngay trong Sổ tay (không có cuộc gốc) -> nhảy tới tin trong chính Sổ tay.
    let moTinTrongSoTay: (Tin) -> Void

    @State private var thang = Calendar.current.dateInterval(of: .month, for: Date())!.start
    @State private var ngayChon = Calendar.current.startOfDay(for: Date())
    @State private var tinTaiThem: [Tin] = []
    @State private var dangTai = false

    private let lich = Calendar.current
    private let tenThuNgan = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]

    var body: some View {
        // v6.0: ScrollView + lưới ngày KHÔNG lazy (bản 5.9 dùng LazyVGrid trong List -> crash khi mở Sổ tay)
        let theoNgay = lanHenTheoNgay
        let ds = theoNgay[ngayChon] ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 10) {
                    dauThang
                    luoiNgay(theoNgay)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { g in
                    if g.translation.width < -50 { doiThang(1) } else if g.translation.width > 50 { doiThang(-1) }
                })

                Text(tieuDeNgay(ngayChon)).font(.subheadline.bold()).foregroundStyle(.secondary).padding(.horizontal, 4)
                VStack(spacing: 0) {
                    if ds.isEmpty {
                        Text(dangTai ? "Đang tải lịch hẹn…" : "Không có lịch hẹn nào")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    }
                    ForEach(Array(ds.enumerated()), id: \.offset) { i, lan in
                        if i > 0 { Divider().padding(.leading, 62) }
                        Button { mo(lan) } label: { HangLichHen(lan: lan).padding(.horizontal, 12).padding(.vertical, 6) }
                            .buttonStyle(.plain)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await taiHet() }
        .task { if tinTaiThem.isEmpty { await taiHet() } }
    }

    // ------------------------------------------------ đầu tháng: < Tháng 10, 2026 >
    private var dauThang: some View {
        HStack {
            Button { doiThang(-1) } label: { Image(systemName: "chevron.left").padding(8) }
            Spacer()
            VStack(spacing: 2) {
                let c = lich.dateComponents([.month, .year], from: thang)
                Text("Tháng \(c.month ?? 1), \(String(c.year ?? 0))").font(.headline)
                if !lich.isDate(thang, equalTo: Date(), toGranularity: .month) || !lich.isDateInToday(ngayChon) {
                    Button("Hôm nay") {
                        thang = lich.dateInterval(of: .month, for: Date())!.start
                        ngayChon = lich.startOfDay(for: Date())
                    }
                    .font(.caption)
                }
            }
            Spacer()
            Button { doiThang(1) } label: { Image(systemName: "chevron.right").padding(8) }
        }
        .buttonStyle(.borderless)
    }

    // ------------------------------------------------ lưới 7 cột, tuần bắt đầu Thứ 2
    private func luoiNgay(_ theoNgay: [Date: [LanHen]]) -> some View {
        let o = cacO
        let soTuan = (o.count + 6) / 7
        return VStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(0..<7, id: \.self) { i in
                    Text(tenThuNgan[i]).font(.caption2.bold()).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<soTuan, id: \.self) { tuan in
                HStack(spacing: 2) {
                    ForEach(0..<7, id: \.self) { thu in
                        oNgay(tuan * 7 + thu < o.count ? o[tuan * 7 + thu] : nil, theoNgay)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func oNgay(_ ngay: Date?, _ theoNgay: [Date: [LanHen]]) -> some View {
        if let ngay {
            let so = theoNgay[ngay]?.count ?? 0
            let chon = ngay == ngayChon
            let homNay = lich.isDateInToday(ngay)
            VStack(spacing: 3) {
                Text("\(lich.component(.day, from: ngay))")
                    .font(.system(size: 15, weight: homNay || chon ? .bold : .regular))
                    .foregroundStyle(chon ? .white : (homNay ? ZaloMau.xanh : .primary))
                    .frame(width: 32, height: 32)
                    .background(chon ? ZaloMau.xanh : Color.clear, in: Circle())
                    .overlay(Circle().strokeBorder(homNay && !chon ? ZaloMau.xanh : .clear, lineWidth: 1.5))
                HStack(spacing: 2) {
                    ForEach(0..<min(so, 3), id: \.self) { _ in
                        Circle().fill(Color.orange).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { ngayChon = ngay }
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: 40)
        }
    }

    /// Các ô của tháng đang xem (nil = ô trống đầu tháng để ngày 1 đúng thứ).
    private var cacO: [Date?] {
        guard let soNgay = lich.range(of: .day, in: .month, for: thang)?.count else { return [] }
        let thuDau = (lich.component(.weekday, from: thang) + 5) % 7   // CN=1 -> 6, T2=2 -> 0
        let ngay = (0..<soNgay).compactMap { lich.date(byAdding: .day, value: $0, to: thang) }
        return Array(repeating: nil, count: thuDau) + ngay.map { Optional($0) }
    }

    private func doiThang(_ buoc: Int) {
        guard let moi = lich.date(byAdding: .month, value: buoc, to: thang) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { thang = moi }
        // chọn ngày 1 của tháng mới (hoặc hôm nay nếu về tháng hiện tại)
        ngayChon = lich.isDate(moi, equalTo: Date(), toGranularity: .month) ? lich.startOfDay(for: Date()) : moi
    }

    private func tieuDeNgay(_ d: Date) -> String {
        DinhDang.ngayDai(Int64(d.timeIntervalSince1970 * 1000))
    }

    // ------------------------------------------------ dữ liệu
    /// Mọi lịch hẹn còn hiệu lực (bỏ trùng theo id lịch, giữ bản mới nhất).
    private var dsLichHen: [(Tin, LichHen)] {
        var theoId: [String: (Tin, LichHen)] = [:]
        for t in tinTaiThem + vm.tinDangXem where t.kieu == "lich" {
            guard let l = t.phu?.lich, l.batDau != nil else { continue }
            let k = l.id ?? t.msgId
            if let cu = theoId[k], cu.0.ts >= t.ts { continue }
            theoId[k] = (t, l)
        }
        return theoId.values.filter { $0.1.daXoa != true }
    }

    /// Các lần hẹn rơi vào tháng đang xem, gom theo ngày, sắp theo giờ.
    private var lanHenTheoNgay: [Date: [LanHen]] {
        guard let khoang = lich.dateInterval(of: .month, for: thang) else { return [:] }
        var kq: [Date: [LanHen]] = [:]
        for (t, l) in dsLichHen {
            let goc = Date(timeIntervalSince1970: TimeInterval(l.batDau ?? 0) / 1000)
            for luc in cacLanTrong(khoang, goc: goc, lap: l.lap ?? 0) {
                kq[lich.startOfDay(for: luc), default: []].append(LanHen(tin: t, lich: l, luc: luc))
            }
        }
        return kq.mapValues { $0.sorted { $0.luc < $1.luc } }
    }

    private func cacLanTrong(_ khoang: DateInterval, goc: Date, lap: Int) -> [Date] {
        let thanhPhan: Calendar.Component
        switch lap {
        case 1: thanhPhan = .day
        case 2: thanhPhan = .weekOfYear
        case 3: thanhPhan = .month
        default: return khoang.contains(goc) ? [goc] : []
        }
        guard goc < khoang.end else { return [] }
        var kq: [Date] = []
        var i = 0
        // nhảy nhanh tới gần đầu tháng rồi mới đếm từng lần
        if goc < khoang.start, let n = lich.dateComponents([thanhPhan], from: goc, to: khoang.start).value(for: thanhPhan) {
            i = max(0, n - 1)
        }
        var vong = 0
        while vong < 500, let luc = lich.date(byAdding: thanhPhan, value: i, to: goc), luc < khoang.end, kq.count < 40 {
            vong += 1
            // lặp tháng: ngày 31 không có ở tháng ngắn -> Calendar lùi về cuối tháng, bỏ qua cho đúng Zalo
            if luc >= khoang.start && (lap != 3 || lich.component(.day, from: luc) == lich.component(.day, from: goc)) {
                kq.append(luc)
            }
            i += 1
        }
        return kq
    }

    /// Tải hết các tin của Sổ tay (mỗi trang 60) để lấy đủ lịch hẹn cũ.
    private func taiHet() async {
        guard !dangTai else { return }
        dangTai = true
        defer { dangTai = false }
        var ds: [Tin] = []
        var truoc: Int64? = nil
        for _ in 0..<40 {
            guard let kq = try? await env.api.dsTin(cuoc: vm.cuoc.id, truoc: truoc) else { break }
            ds += kq.tin
            guard kq.tin.count >= 60, let cuNhat = kq.tin.map(\.ts).min() else { break }
            truoc = cuNhat
        }
        if !ds.isEmpty { tinTaiThem = ds }
    }

    // ------------------------------------------------ bấm 1 lịch hẹn -> về đúng tin tạo lịch
    private func mo(_ lan: LanHen) {
        let l = lan.lich
        let laSoTay: (String) -> Bool = { $0 == "so-tay" || $0 == "so_tay" || $0 == vm.cuoc.id }
        if let nguon = l.cuocNguon, !nguon.isEmpty, !laSoTay(nguon) {
            env.moCuocHoiThoai(cuocId: nguon, tenCuoc: l.tenCuoc, msgId: l.msgNguon, quanhTs: l.taoLuc ?? lan.tin.ts)
        } else if let c = l.cuocLich, !c.isEmpty, !laSoTay(c) {
            env.moCuocHoiThoai(cuocId: c, tenCuoc: l.tenCuoc, msgId: l.msgNguon, quanhTs: l.taoLuc ?? lan.tin.ts)
        } else {
            moTinTrongSoTay(lan.tin)
        }
    }
}

private struct HangLichHen: View {
    let lan: LanHen

    var body: some View {
        HStack(spacing: 12) {
            Text(lan.lich.emoji ?? "⏰")
                .font(.system(size: 22))
                .frame(width: 38, height: 38)
                .background(Color(.systemGray5), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(lan.lich.tieuDe ?? "Lịch hẹn").font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary).lineLimit(2)
                HStack(spacing: 6) {
                    Label(DinhDang.gioPhut(Int64(lan.luc.timeIntervalSince1970 * 1000)), systemImage: "clock")
                    if let lap = chuLap { Text("· " + lap) }
                }
                .font(.caption)
                .foregroundStyle(lan.luc < Date() ? Color.secondary : ZaloMau.xanh)
                if let ten = lan.lich.tenCuoc, !ten.isEmpty {
                    Text("Từ: \(ten)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private var chuLap: String? {
        switch lan.lich.lap {
        case 1: return "Hằng ngày"
        case 2: return "Hằng tuần"
        case 3: return "Hằng tháng"
        default: return nil
        }
    }
}
