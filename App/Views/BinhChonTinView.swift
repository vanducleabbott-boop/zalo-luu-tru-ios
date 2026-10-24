// Thẻ cuộc bình chọn Zalo (Poll) - hiển thị câu hỏi, các lựa chọn, số phiếu, thanh tiến trình,
// cho phép bình chọn trực tiếp, xem chi tiết ai đã bình chọn và cập nhật thời gian thực.

import SwiftUI

struct BinhChonTinView: View {
    @EnvironmentObject var env: AppEnvironment
    /// Chỉ dùng để gọi bỏ phiếu - KHÔNG @ObservedObject (mỗi thay đổi của vm vẽ lại mọi thẻ bình chọn).
    let vm: ChatViewModel
    let bc: BinhChonInfo

    @State private var luaChonHienTai: Set<Int> = []
    @State private var dangGui = false
    @State private var hienChiTiet = false
    @State private var thongBaoLoi: String? = nil

    private var choPhepChonNhieu: Bool { bc.allowMultiChoices == true }
    private var daKetThuc: Bool { bc.isClosed == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.blue)

                Text("Bình chọn")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.blue)

                Spacer()

                if daKetThuc {
                    Text("Đã kết thúc")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.12), in: Capsule())
                } else if choPhepChonNhieu {
                    Text("Chọn nhiều")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5), in: Capsule())
                }
            }

            // Câu hỏi bình chọn
            Text(bc.cauHoi)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.primary)
                .lineLimit(3)

            Divider()

            // Danh sách lựa chọn
            VStack(spacing: 8) {
                ForEach(bc.options) { opt in
                    hangLuaChon(opt)
                }
            }

            // Nút bình chọn / đổi lựa chọn
            if !daKetThuc {
                if luaChonDaThayDoi {
                    Button {
                        guiBinhChon()
                    } label: {
                        HStack(spacing: 6) {
                            if dangGui {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13))
                            }
                            Text(bc.myVotes?.isEmpty == false ? "Thay đổi bình chọn" : "Bình chọn")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(dangGui || luaChonHienTai.isEmpty)
                }
            }

            // Xem kết quả chi tiết
            Button {
                hienChiTiet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11))
                    let tongPhieu = bc.totalVotes ?? bc.options.reduce(0) { $0 + $1.votes }
                    Text("Xem kết quả (\(tongPhieu) lượt) & người bình chọn")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Color.blue)
                .padding(.top, 2)
            }
            .buttonStyle(.plain)

            if let loi = thongBaoLoi {
                Text(loi)
                    .font(.caption2)
                    .foregroundStyle(Color.red)
            }
        }
        .padding(12)
        .frame(minWidth: 260, maxWidth: 300, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.systemGray4).opacity(0.6), lineWidth: 1)
        )
        .onAppear {
            khoiTaoLuaChon()
        }
        .task(id: bc.pollId) { await napTenNguoiBinhChon(bc, env: env) }
        .onChange(of: bc.myVotes) { _ in
            khoiTaoLuaChon()
        }
        .sheet(isPresented: $hienChiTiet) {
            ChiTietBinhChonSheet(bc: bc, vm: vm)
        }
    }

    private func khoiTaoLuaChon() {
        if let mv = bc.myVotes {
            luaChonHienTai = Set(mv)
        } else {
            let votedOpts = bc.options.filter { $0.voted == true }.map { $0.optionId }
            luaChonHienTai = Set(votedOpts)
        }
    }

    private var luaChonDaThayDoi: Bool {
        let goc = Set(bc.myVotes ?? bc.options.filter { $0.voted == true }.map { $0.optionId })
        return luaChonHienTai != goc
    }

    @ViewBuilder
    private func hangLuaChon(_ opt: BinhChonLuaChon) -> some View {
        let isSelected = luaChonHienTai.contains(opt.optionId)
        let phanTram = tinhPhanTram(opt)

        Button {
            guard !daKetThuc else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if choPhepChonNhieu {
                if luaChonHienTai.contains(opt.optionId) {
                    luaChonHienTai.remove(opt.optionId)
                } else {
                    luaChonHienTai.insert(opt.optionId)
                }
            } else {
                luaChonHienTai = [opt.optionId]
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? (choPhepChonNhieu ? "checkmark.square.fill" : "largecircle.fill.circle") : (choPhepChonNhieu ? "square" : "circle"))
                        .font(.system(size: 15))
                        .foregroundStyle(isSelected ? Color.blue : Color.secondary)

                    Text(opt.content)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)

                    Spacer(minLength: 4)

                    Text("\(opt.votes)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.secondary)
                }

                // Thanh tiến trình tỉ lệ bình chọn
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.systemGray5))
                            .frame(height: 6)

                        Capsule()
                            .fill(isSelected ? Color.blue : Color.blue.opacity(0.5))
                            .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(phanTram / 100.0))), height: 6)
                    }
                }
                .frame(height: 6)

                // Dòng hiển thị % và người vote tóm tắt
                HStack {
                    Text(String(format: "%.1f%%", phanTram))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    if let voters = opt.voters, !voters.isEmpty, bc.isAnonymous != true {
                        HStack(spacing: -5) {
                            ForEach(Array(voters.prefix(3)), id: \.self) { uid in
                                AvatarView(ten: env.tenNguoi(uid: uid, macDinh: "Người"), anh: env.anhNguoi(uid: uid), khoa: uid, kichThuoc: 14)
                            }
                        }
                    }
                }
            }
            .padding(8)
            .background(isSelected ? Color.blue.opacity(0.08) : Color(.systemGray6).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func tinhPhanTram(_ opt: BinhChonLuaChon) -> Double {
        if let p = opt.percentage { return p }
        let tong = Double(bc.totalVotes ?? bc.options.reduce(0) { $0 + $1.votes })
        guard tong > 0 else { return 0 }
        return (Double(opt.votes) / tong) * 100.0
    }

    private func guiBinhChon() {
        dangGui = true
        thongBaoLoi = nil
        Task {
            do {
                _ = try await vm.boPhieu(pollId: bc.pollId, optionIds: luaChonHienTai.sorted())
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } catch {
                thongBaoLoi = "Lỗi bỏ phiếu: " + error.localizedDescription
            }
            dangGui = false
        }
    }
}

// ---------------------------------------------------------------- Sheet xem chi tiết kết quả & người tham gia bình chọn
struct ChiTietBinhChonSheet: View {
    let bc: BinhChonInfo
    let vm: ChatViewModel
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var chiTietMoi: BinhChonInfo? = nil
    @State private var dangTaiLai = false

    private var info: BinhChonInfo { chiTietMoi ?? bc }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(info.cauHoi)
                            .font(.system(size: 17, weight: .bold))

                        HStack(spacing: 8) {
                            let tong = info.totalVotes ?? info.options.reduce(0) { $0 + $1.votes }
                            Text("\(tong) lượt bình chọn")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)

                            if info.isAnonymous == true {
                                Text("• Bình chọn ẩn danh")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                            if info.allowMultiChoices == true {
                                Text("• Chọn nhiều")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                ForEach(info.options) { opt in
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(opt.content)
                                    .font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Text("\(opt.votes) phiếu")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.blue)
                            }

                            // Danh sách người đã chọn phương án này
                            if info.isAnonymous == true {
                                Text("Bình chọn ẩn danh, không xem được danh sách người tham gia.")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            } else if let voters = opt.voters, !voters.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(voters, id: \.self) { uid in
                                        HStack(spacing: 8) {
                                            AvatarView(ten: env.tenNguoi(uid: uid, macDinh: "Người tham gia"), anh: env.anhNguoi(uid: uid), khoa: uid, kichThuoc: 24)
                                            Text(env.tenNguoi(uid: uid, macDinh: "Người dùng"))
                                                .font(.system(size: 13))
                                            if uid == env.uidToi {
                                                Text("(Bạn)")
                                                    .font(.caption2.bold())
                                                    .foregroundStyle(Color.blue)
                                            }
                                        }
                                    }
                                }
                                .padding(.top, 4)
                            } else {
                                Text("Chưa có ai chọn phương án này")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Kết quả bình chọn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        taiLai()
                    } label: {
                        if dangTaiLai {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .onAppear {
            taiLai()
        }
    }

    private func taiLai() {
        guard !dangTaiLai else { return }
        dangTaiLai = true
        Task {
            if let moi = try? await env.api.layChiTietBinhChon(pollId: bc.pollId) {
                chiTietMoi = moi
                await napTenNguoiBinhChon(moi, env: env)
            }
            dangTaiLai = false
        }
    }
}

/// Nạp tên/ảnh những người đã bình chọn (trước đây chưa nạp -> hiện "Người"/"Người dùng").
@MainActor
private func napTenNguoiBinhChon(_ bc: BinhChonInfo, env: AppEnvironment) async {
    let uids = Set(bc.options.flatMap { $0.voters ?? [] }).filter { env.nguoiCache[$0] == nil }
    if !uids.isEmpty { await env.napNguoi(Array(uids)) }
}
