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

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(vm.danhSachHienThi.enumerated()), id: \.offset) { i, muc in
                        switch muc {
                        case .ngay(let nhan):
                            MocNgayView(nhan: nhan)
                                .listRowSeparator(.hidden).listRowInsets(EdgeInsets())
                                .onAppear { if i < 3 { Task { await vm.taiTinCu() } } }
                        case .tin(let t, let dauNhom, let cuoiNhom):
                            MessageBubble(vm: vm, t: t, dauNhom: dauNhom, cuoiNhom: cuoiNhom,
                                          laNhom: vm.cuoc.laNhomBool,
                                          chamTrichDan: { denTin($0) },
                                          chonChuyenTiep: { tinChuyenTiep = $0 },
                                          anhDangXem: $anhDangXem,
                                          videoDangXem: $videoDangXem,
                                          fileDangXem: $fileDangXem)
                                .id(t.msgId)
                                .listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
                                .onAppear { if i < 3 { Task { await vm.taiTinCu() } } }
                        case .album(let ds, let dauNhom, let cuoiNhom):
                            // v4.3: nhiều ảnh/video gửi 1 lần -> 1 khung lưới (id = tin cuối để cuộn xuống đáy đúng)
                            MessageBubble(vm: vm, t: ds[0], dauNhom: dauNhom, cuoiNhom: cuoiNhom,
                                          laNhom: vm.cuoc.laNhomBool,
                                          chamTrichDan: { denTin($0) },
                                          chonChuyenTiep: { tinChuyenTiep = $0 },
                                          anhDangXem: $anhDangXem,
                                          videoDangXem: $videoDangXem,
                                          fileDangXem: $fileDangXem,
                                          album: ds)
                                .id(ds[ds.count - 1].msgId)
                                .listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
                                .onAppear { if i < 3 { Task { await vm.taiTinCu() } } }
                        }
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
            }
            if let traLoi = vm.traLoi { ThanhTraLoiView(t: traLoi) { vm.boTraLoi() } }
            MessageInputBar(vm: vm, daFocus: $daFocusNhap, onMoLichHen: { hienTaoLich = true })
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
        .sheet(item: $anhDangXem) { a in ImageViewerView(anh: a) }
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
