import SwiftUI
import QuickLook

final class ChatViewModelHolder: ObservableObject {
    @Published var vm: ChatViewModel?
}

struct ChatView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var holder = ChatViewModelHolder()
    let cuoc: Cuoc
    var quanhTs: Int64?
    var sangMsgId: String?

    init(cuoc: Cuoc, quanhTs: Int64? = nil, sangMsgId: String? = nil) {
        self.cuoc = cuoc; self.quanhTs = quanhTs; self.sangMsgId = sangMsgId
    }


    var body: some View {
        Group {
            if let vm = holder.vm {
                ChatContentView(vm: vm)
            } else {
                ProgressView()
            }
        }
        .task {
            if holder.vm == nil {
                let vm = ChatViewModel(cuoc: cuoc, env: env)
                holder.vm = vm
                await vm.taiLan1(quanh: quanhTs, sangMsgId: sangMsgId)
            }
        }
    }
}

private struct ChatContentView: View {
    @State private var showDsGhimSheet = false
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject var vm: ChatViewModel
    @FocusState private var daFocusNhap: Bool
    @State private var anhDangXem: AnhXemToan?
    @State private var videoDangXem: VideoXemToan?
    @State private var fileDangXem: URL?
    @State private var tinChuyenTiep: Tin?
    @State private var hienKho = false
    @State private var hienTimTrong = false
    @State private var hienTaoLich = false

    @ViewBuilder
    private var thanhGhimNeuCo: some View {
        if !vm.dsGhim.isEmpty {
            ThanhTinGhimView(dsGhim: vm.dsGhim, onNhayToi: { msgId in
                withAnimation(.easeInOut(duration: 0.3)) {
                    vm.tinDuocNhayToi = msgId
                }
            }, onXemTatCa: {
                showDsGhimSheet = true
            })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            thanhGhimNeuCo

            ScrollViewReader { proxy in
                List {
                    ForEach(Array(vm.danhSachHienThi.enumerated()), id: \.offset) { i, muc in
                        ChatRowItemView(
                            i: i,
                            muc: muc,
                            vm: vm,
                            chamTrichDan: { denTin($0) },
                            chonChuyenTiep: { tinChuyenTiep = $0 },
                            anhDangXem: $anhDangXem,
                            videoDangXem: $videoDangXem,
                            fileDangXem: $fileDangXem
                        )
                    }
                    Color.clear.frame(height: 1).id("__day_chat__")
                        .listRowSeparator(.hidden).listRowInsets(EdgeInsets())
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(ZaloMau.nenChat)
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    cuonXuongDay(proxy: proxy, animate: false)
                    Task { await vm.taiTinGhim() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        cuonXuongDay(proxy: proxy, animate: false)
                    }
                }
                .onChange(of: vm.tinDangXem.count) { soLuong in
                    if soLuong > 0 && !vm.daCuonXuongCuoiLanDau {
                        cuonXuongDay(proxy: proxy, animate: false)
                    }
                }
                .onChange(of: vm.cuonToiMsgId) { moi in
                    guard let moi else { return }
                    if moi == "__cuoi__" || moi == "__cuoi_neu_sat_day__" {
                        cuonXuongDay(proxy: proxy, animate: moi != "__cuoi__")
                    } else {
                        withAnimation { proxy.scrollTo(moi, anchor: .center) }
                    }
                    vm.cuonToiMsgId = nil
                }
                .onChange(of: vm.traLoi?.msgId) { moi in
                    if moi != nil {
                        daFocusNhap = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            cuonXuongDay(proxy: proxy, animate: true)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        cuonXuongDay(proxy: proxy, animate: true)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                    cuonXuongDay(proxy: proxy, animate: true)
                }
                .onChange(of: vm.tinDuocNhayToi) { targetId in
                    guard let tid = targetId, !tid.isEmpty else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(tid, anchor: .center)
                    }
                }
            }
            if let traLoi = vm.traLoi { ThanhTraLoiView(t: traLoi) { vm.boTraLoi() } }
            MessageInputBar(vm: vm, daFocus: $daFocusNhap, onMoLichHen: { hienTaoLich = true })
        }
        .sheet(isPresented: $showDsGhimSheet) {
            DanhSachTinGhimSheet(dsGhim: vm.dsGhim, onChon: { msgId in
                showDsGhimSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    vm.tinDuocNhayToi = msgId
                }
            }, onBoGhim: { msgId in
                Task {
                    await vm.chuyenTrangThaiGhim(msgId: msgId, ghim: false)
                }
            })
        }
        .navigationTitle(vm.cuoc.ten ?? vm.cuoc.id)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    AvatarView(ten: vm.cuoc.ten ?? vm.cuoc.id, anh: vm.cuoc.anh, khoa: vm.cuoc.id, kichThuoc: 32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(vm.cuoc.ten ?? vm.cuoc.id).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text(vm.cuoc.id == "so-tay" ? "Ghi chú & lịch hẹn riêng" : (vm.cuoc.laNhomBool ? "Nhóm" : "Trò chuyện cá nhân"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { hienTaoLich = true } label: { Label("Đặt lịch hẹn", systemImage: "calendar.badge.clock") }
                    Button { hienTimTrong = true } label: { Label("Tìm tin nhắn", systemImage: "magnifyingglass") }
                    Button { hienKho = true } label: { Label("Ảnh, file, link đã gửi", systemImage: "photo.on.rectangle") }
                    if vm.cuoc.id != "so-tay" {
                        Button { Task { await datGhim() } } label: {
                            Label(vm.cuoc.daGhim ? "Bỏ ghim" : "Ghim hội thoại", systemImage: "pin")
                        }
                        if vm.cuoc.laNhomBool {
                            Button { Task { await datTat() } } label: {
                                Label(vm.cuoc.daTatThongBao ? "Bật lại thông báo" : "Tắt thông báo nhóm", systemImage: "bell.slash")
                            }
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $hienTaoLich) { TaoLichHenView(vm: vm) }
        .sheet(isPresented: $hienKho) {
            MediaGalleryView(cuocId: vm.cuoc.id) { tinChon in
                denTin(tinChon.msgId, ts: tinChon.ts)
            }
        }
        .sheet(isPresented: $hienTimTrong) { SearchInConversationView(vm: vm) }
        .sheet(item: $tinChuyenTiep) { t in ForwardMessageView(tin: t, cuocGocId: vm.cuoc.id) }
        .sheet(item: $anhDangXem) { a in ImageViewerView(anh: a, cuocId: vm.cuoc.id) }
        .fullScreenCover(item: $videoDangXem) { v in TrinhPhatVideoView(url: v.url) }
        .quickLookPreview($fileDangXem)
        .alert("Lỗi", isPresented: Binding(get: { vm.loi != nil }, set: { if !$0 { vm.loi = nil } })) {
            Button("Đóng", role: .cancel) {}
        } message: { Text(vm.loi ?? "") }
    }

    private func denTin(_ msgId: String, ts: Int64? = nil) {
        guard !msgId.isEmpty else { return }
        if vm.tinDangXem.contains(where: { $0.msgId == msgId }) {
            vm.cuonToiMsgId = msgId
        } else {
            Task { await vm.taiLan1(quanh: ts, sangMsgId: msgId) }
        }
    }

    private func datGhim() async {
        do { _ = try await env.api.datGhim(cuoc: vm.cuoc.id, bat: !vm.cuoc.daGhim) } catch { vm.loi = error.localizedDescription }
    }
    private func datTat() async {
        do { try await env.api.datTatThongBao(cuoc: vm.cuoc.id, tat: !vm.cuoc.daTatThongBao) } catch { vm.loi = error.localizedDescription }
    }

    private func cuonXuongDay(proxy: ScrollViewProxy, animate: Bool) {
        let thucHien = {
            if let cuoi = vm.tinDangXem.last?.msgId {
                proxy.scrollTo(cuoi, anchor: .bottom)
            }
            proxy.scrollTo("__day_chat__", anchor: .bottom)
        }
        if animate {
            withAnimation(.easeOut(duration: 0.25)) { thucHien() }
        } else {
            thucHien()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if animate { withAnimation(.easeOut(duration: 0.2)) { thucHien() } } else { thucHien() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if animate { withAnimation(.easeOut(duration: 0.2)) { thucHien() } } else { thucHien() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if animate { withAnimation(.easeOut(duration: 0.2)) { thucHien() } } else { thucHien() }
            vm.daCuonXuongCuoiLanDau = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            thucHien()
        }
    }
}

struct MocNgayView: View {
    let nhan: String
    var body: some View {
        Text(nhan).font(.caption).foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 3)
            .background(.black.opacity(0.28), in: Capsule())
            .frame(maxWidth: .infinity).padding(.vertical, 6)
    }
}

struct ThanhTraLoiView: View {
    let t: Tin
    let boQua: () -> Void
    var body: some View {
        HStack {
            TrichDanXemTruoc(q: TrichDan(ten: t.laToi ? "Bạn" : t.tenNguoi, chu: t.chu ?? xemTruoc(t), msgId: t.msgId))
            Spacer()
            Button(action: boQua) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 12).padding(.top, 6)
    }
    private func xemTruoc(_ t: Tin) -> String {
        ["anh": "[Hình ảnh]", "video": "[Video]", "ghiam": "[Tin nhắn thoại]", "sticker": "[Sticker]"][t.kieu] ?? ""
    }
}


// MARK: - Thanh hiển thị tin nhắn ghim (banner trên đầu khung chat)
struct ThanhTinGhimView: View {
    let dsGhim: [TinGhim]
    let onNhayToi: (String) -> Void
    let onXemTatCa: () -> Void

    var tinMoiNhat: TinGhim? {
        dsGhim.first
    }

    private var tieuDeText: String {
        guard let g = tinMoiNhat else { return "" }
        if let t = g.tieuDe, !t.isEmpty { return t }
        return "[Tin nhắn]"
    }

    private var nguoiText: String {
        if let n = tinMoiNhat?.nguoiGhim, !n.isEmpty {
            return "• " + n
        }
        return ""
    }

    private var labelGhim: String {
        if dsGhim.count > 1 {
            return "Tin nhắn ghim (\(dsGhim.count))"
        }
        return "Tin nhắn ghim"
    }

    var body: some View {
        if let g = tinMoiNhat {
            HStack(spacing: 10) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.orange)
                    .rotationEffect(.degrees(45))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(labelGhim)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)

                        if !nguoiText.isEmpty {
                            Text(nguoiText)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    Text(tieuDeText)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if dsGhim.count > 1 {
                    Button(action: onXemTatCa) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(6)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(UIColor.secondarySystemBackground))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.gray.opacity(0.2)),
                alignment: .bottom
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onNhayToi(g.msgId)
            }
        }
    }
}

// MARK: - Sheet danh sách tất cả tin nhắn ghim
struct DanhSachTinGhimSheet: View {
    let dsGhim: [TinGhim]
    let onChon: (String) -> Void
    let onBoGhim: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(dsGhim) { g in
                    GhimDongRow(g: g, onChon: onChon, onBoGhim: onBoGhim)
                }
            }
            .navigationTitle("Tin nhắn ghim (\(dsGhim.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct GhimDongRow: View {
    let g: TinGhim
    let onChon: (String) -> Void
    let onBoGhim: (String) -> Void

    private var hienThiTieuDe: String {
        if let t = g.tieuDe, !t.isEmpty { return t }
        return "[Tin nhắn]"
    }

    var body: some View {
        Button(action: {
            onChon(g.msgId)
        }) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
                    .rotationEffect(.degrees(45))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    if let nguoi = g.nguoiGhim, !nguoi.isEmpty {
                        Text(nguoi)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }

                    Text(hienThiTieuDe)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .lineLimit(3)
                }

                Spacer()

                Button(action: {
                    onBoGhim(g.msgId)
                }) {
                    Image(systemName: "pin.slash")
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .padding(6)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .padding(.vertical, 4)
        }
    }
}


// MARK: - Row item con trong danh sách chat (giúp giải tỏa tải biên dịch cho Swift compiler)
private struct ChatRowItemView: View {
    let i: Int
    let muc: MucHienThi
    @ObservedObject var vm: ChatViewModel
    let chamTrichDan: (String) -> Void
    let chonChuyenTiep: (Tin) -> Void
    @Binding var anhDangXem: AnhXemToan?
    @Binding var videoDangXem: VideoXemToan?
    @Binding var fileDangXem: URL?

    var body: some View {
        switch muc {
        case .ngay(let nhan):
            MocNgayView(nhan: nhan)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .onAppear { if i < 3 { Task { await vm.taiTinCu() } } }
        case .tin(let t, let dauNhom, let cuoiNhom):
            MessageBubble(vm: vm, t: t, dauNhom: dauNhom, cuoiNhom: cuoiNhom,
                          laNhom: vm.cuoc.laNhomBool,
                          chamTrichDan: chamTrichDan,
                          chonChuyenTiep: chonChuyenTiep,
                          anhDangXem: $anhDangXem,
                          videoDangXem: $videoDangXem,
                          fileDangXem: $fileDangXem)
                .id(t.msgId)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
                .onAppear { if i < 3 { Task { await vm.taiTinCu() } } }
        case .album(let ds, let dauNhom, let cuoiNhom):
            MessageBubble(vm: vm, t: ds[0], dauNhom: dauNhom, cuoiNhom: cuoiNhom,
                          laNhom: vm.cuoc.laNhomBool,
                          chamTrichDan: chamTrichDan,
                          chonChuyenTiep: chonChuyenTiep,
                          anhDangXem: $anhDangXem,
                          videoDangXem: $videoDangXem,
                          fileDangXem: $fileDangXem,
                          album: ds)
                .id(ds[ds.count - 1].msgId)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
                .onAppear { if i < 3 { Task { await vm.taiTinCu() } } }
        }
    }
}
