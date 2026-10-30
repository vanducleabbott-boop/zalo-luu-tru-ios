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

    private var laSoTay: Bool { cuoc.id == "so-tay" || cuoc.id == "so_tay" }

    var body: some View {
        Group {
            if let vm = holder.vm {
                if laSoTay {
                    SoTayView(vm: vm, moLichTruoc: sangMsgId == nil)
                } else {
                    ChatContentView(vm: vm)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            if holder.vm == nil {
                let vm = ChatViewModel(cuoc: cuoc, env: env)
                holder.vm = vm
                // v5.9: mở tới 1 tin cụ thể (lịch hẹn, kết quả tìm...) -> viền cam đánh dấu đúng tin đó
                if let sangMsgId { vm.tinDuocNhayToi = sangMsgId }
                await vm.taiLan1(quanh: quanhTs, sangMsgId: sangMsgId)
            }
        }
    }
}

/// v5.9: Sổ tay = 2 chế độ: "Lịch" (lịch tháng các lịch hẹn) và "Ghi chú" (dòng tin như cũ).
private struct SoTayView: View {
    @ObservedObject var vm: ChatViewModel
    @State private var cheDo: Int

    init(vm: ChatViewModel, moLichTruoc: Bool) {
        self.vm = vm
        _cheDo = State(initialValue: moLichTruoc ? 0 : 1)
    }

    var body: some View {
        Group {
            if cheDo == 0 {
                SoTayLichView(vm: vm) { t in
                    cheDo = 1
                    vm.tinDuocNhayToi = t.msgId
                    if vm.tinDangXem.contains(where: { $0.msgId == t.msgId }) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { vm.cuonToiMsgId = t.msgId }
                    } else {
                        Task { await vm.taiLan1(quanh: t.ts, sangMsgId: t.msgId) }
                    }
                }
                .navigationTitle("📒 Sổ tay")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ChatContentView(vm: vm)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("", selection: $cheDo) {
                Text("📅 Lịch").tag(0)
                Text("📝 Ghi chú").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.bar)
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
    @State private var showDsGhimSheet = false
    /// v5.4: đáy chat đang trong màn hình -> mới tự cuộn khi có tin mới (trước luôn kéo tuột xuống đáy).
    @State private var dangSatDay = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                // v7.0: List (UICollectionView) trên iOS 26 gộp cập nhật dữ liệu rồi mới áp dụng -> lệnh cuộn
                // tới tin mới chạy trước khi List có dòng đó -> "_validateScrollingTargetIndexPath" văng app
                // (crash log 30/10 khi bấm thông báo). LazyVStack cuộn tới id chưa có thì bỏ qua, không văng.
                ScrollView {
                  LazyVStack(spacing: 0) {
                    ForEach(Array(vm.mucCoKhoa.enumerated()), id: \.element.khoa) { i, phan in
                        switch phan.muc {
                        case .ngay(let nhan):
                            MocNgayView(nhan: nhan)
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
                                .padding(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
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
                                .padding(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
                                .onAppear { if i < 3 { Task { await vm.taiTinCu() } } }
                        }
                    }
                    Color.clear.frame(height: 1).id("__day_chat__")
                        .onAppear { dangSatDay = true }
                        .onDisappear { dangSatDay = false }
                  }
                  .padding(.vertical, 4)
                }
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
                    if moi == "__cuoi__" {
                        cuonXuongDay(proxy: proxy, animate: false)
                    } else if moi == "__cuoi_neu_sat_day__" {
                        // đang kéo lên đọc tin cũ thì để yên, không giật xuống đáy
                        if dangSatDay { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("__day_chat__", anchor: .bottom) } }
                    } else {
                        // v6.9: cuộn ở lượt sau (List đã nhận dữ liệu mới) và chỉ khi tin có trong danh sách,
                        // nếu không (tin từ thông báo chưa tải về) thì xuống đáy - trước đây cuộn tới id lạ làm crash.
                        DispatchQueue.main.async {
                            if vm.tinDangXem.contains(where: { $0.msgId == moi }) {
                                withAnimation { proxy.scrollTo(moi, anchor: .center) }
                            } else {
                                cuonXuongDay(proxy: proxy, animate: false)
                            }
                        }
                    }
                    vm.cuonToiMsgId = nil
                }
                .onChange(of: vm.giuViTriKhoa) { khoa in
                    // v5.4: vừa chèn trang tin cũ lên đầu -> đứng yên ở tin đang xem thay vì bị đẩy vọt lên
                    guard let khoa else { return }
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) { proxy.scrollTo(khoa, anchor: .top) }
                    vm.giuViTriKhoa = nil
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
                        .onTapGesture { xemAnhDaiDien() }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(vm.cuoc.ten ?? vm.cuoc.id).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text(vm.cuoc.id == "so-tay" ? "Ghi chú & lịch hẹn riêng" : (vm.cuoc.laNhomBool ? "Nhóm" : "Trò chuyện cá nhân"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if coAnhDaiDien {
                        Button { xemAnhDaiDien() } label: { Label("Xem ảnh đại diện", systemImage: "person.crop.circle") }
                    }
                    Button { hienTaoLich = true } label: { Label("Đặt lịch hẹn", systemImage: "calendar.badge.clock") }
                    Button { hienTimTrong = true } label: { Label("Tìm tin nhắn", systemImage: "magnifyingglass") }
                    Button { hienKho = true } label: { Label("Ảnh, file, link đã gửi", systemImage: "photo.on.rectangle") }
                    Button { showDsGhimSheet = true } label: {
                        Label(vm.dsGhim.isEmpty ? "Tin nhắn đã ghim" : "Tin nhắn đã ghim (\(vm.dsGhim.count))", systemImage: "pin.fill")
                    }
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
        .safeAreaInset(edge: .top) {
            if !vm.dsGhim.isEmpty {
                ThanhTinGhimView(dsGhim: vm.dsGhim, onNhayToi: { msgId in
                    denTin(msgId)
                    vm.tinDuocNhayToi = msgId
                }, onXemTatCa: {
                    showDsGhimSheet = true
                })
            }
        }
        .sheet(isPresented: $showDsGhimSheet) {
            DanhSachTinGhimSheet(dsGhim: vm.dsGhim, onChon: { msgId in
                showDsGhimSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    denTin(msgId)
                    vm.tinDuocNhayToi = msgId
                }
            }, onBoGhim: { msgId in
                Task {
                    await vm.chuyenTrangThaiGhim(msgId: msgId, ghim: false)
                }
            })
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

    /// v7.5: chat riêng = mã cuộc là uid người kia -> lấy ảnh gốc; nhóm thì xem ảnh nhóm đang có.
    private var coAnhDaiDien: Bool { vm.cuoc.id != "so-tay" && vm.cuoc.id != "so_tay" && (vm.cuoc.anh != nil || !vm.cuoc.laNhomBool) }

    private func xemAnhDaiDien() {
        guard coAnhDaiDien else { return }
        if vm.cuoc.laNhomBool {
            if let s = vm.cuoc.anh, let url = URL(string: s) { anhDangXem = AnhXemToan(url: url, msgId: "avatar_" + vm.cuoc.id) }
            return
        }
        Task {
            if let a = await MessageBubble.anhDaiDien(env: env, uid: vm.cuoc.id, duPhong: vm.cuoc.anh ?? env.anhNguoi(uid: vm.cuoc.id)) {
                anhDangXem = a
            }
        }
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
