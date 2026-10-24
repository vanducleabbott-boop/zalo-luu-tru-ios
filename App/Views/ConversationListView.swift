import SwiftUI

/// Hộp bọc StateObject-lazy: ViewModel cần `env` (chỉ có qua @EnvironmentObject trong body) nên phải
/// khởi tạo trong .task thay vì init() của View.
final class ConversationListViewModelBox: ObservableObject {
    @Published var vm: ConversationListViewModel?
    @Published var tim: TimKiemViewModel?
}

struct ConversationListView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var holder = ConversationListViewModelBox()

    var body: some View {
        Group {
            if let vm = holder.vm, let tim = holder.tim {
                ConversationListContentView(vm: vm, tim: tim)
            } else {
                ProgressView()
            }
        }
        .task {
            if holder.vm == nil {
                let vm = ConversationListViewModel(env: env)
                holder.tim = TimKiemViewModel(env: env)
                holder.vm = vm
                await vm.tai()
            }
        }
    }
}

/// Đăng ký trực tiếp @ObservedObject vào ConversationListViewModel (chứ không qua holder) để View này
/// được vẽ lại mỗi khi dsCuoc/ketQuaTim.../tuKhoaTim thay đổi - @Published lồng trong 1 object khác
/// không tự lan toả lên View nếu không có bước này.
private struct ConversationListContentView: View {
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject var vm: ConversationListViewModel
    @ObservedObject var tim: TimKiemViewModel
    @State private var cuocCanGanNhom: Cuoc?
    @State private var hienSheetQuetQR = false

    var body: some View {
        NavigationStack(path: $env.duongDanChat) {
            Group {
                if tim.dangTimKiem {
                    KetQuaTimKiemView(tim: tim)
                } else if vm.dsCuoc.isEmpty && !vm.dangTai {
                    VStack(spacing: 10) {
                        Image(systemName: "tray").font(.system(size: 40)).foregroundStyle(.secondary)
                        Text("Chưa có tin nhắn nào được lưu").font(.headline)
                        Text("Tin Zalo mới đến sẽ hiện ở đây.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    danhSach
                }
            }
            .navigationTitle("Tin nhắn")
            .searchable(text: $tim.tuKhoa, prompt: "Tìm người, nhóm, tin nhắn, file")
            .refreshable { await vm.tai() }
            .navigationDestination(for: Cuoc.self) { c in ChatView(cuoc: c) }
            .navigationDestination(for: YeuCauMoCuoc.self) { yc in
                ChatView(cuoc: yc.cuoc, quanhTs: yc.quanhTs, sangMsgId: yc.sangMsgId)
            }
            .navigationDestination(for: TimKiemDiem.self) { diem in
                ChatView(cuoc: diem.cuoc, quanhTs: diem.tin.ts, sangMsgId: diem.tin.msgId)
            }
            .sheet(item: $cuocCanGanNhom) { c in
                ChonNhomChoCuocSheet(cuoc: c)
            }
            .sheet(isPresented: $hienSheetQuetQR) {
                ZaloQRLoginView()
            }
        }
    }

    private var danhSach: some View {
        List {
            if let st = env.zaloServerStatus, !st.daDangNhap {
                Section {
                    Button {
                        hienSheetQuetQR = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Chưa kết nối Zalo Web")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                Text("Bấm vào đây để quét mã QR đăng nhập lại")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            ForEach(vm.dsCuoc) { c in
                NavigationLink(value: c) { ConversationRow(c: c) }
                    .swipeActions(edge: .trailing) { nutThaoTac(c) }
                    .contextMenu {
                        Button {
                            cuocCanGanNhom = c
                        } label: {
                            Label("Thêm vào nhóm…", systemImage: "folder.badge.plus")
                        }
                        Divider()
                        if c.id != "so-tay" {
                            Button {
                                Task { await vm.datGhim(c, bat: !c.daGhim) }
                            } label: {
                                Label(c.daGhim ? "Bỏ ghim" : "Ghim", systemImage: c.daGhim ? "pin.slash" : "pin")
                            }
                            if c.laNhomBool {
                                Button {
                                    Task { await vm.datTatThongBao(c, tat: !c.daTatThongBao) }
                                } label: {
                                    Label(c.daTatThongBao ? "Bật thông báo" : "Tắt thông báo", systemImage: c.daTatThongBao ? "bell" : "bell.slash")
                                }
                            }
                        }
                    }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func nutThaoTac(_ c: Cuoc) -> some View {
        if c.id != "so-tay" {
            Button(c.daGhim ? "Bỏ ghim" : "Ghim") { Task { await vm.datGhim(c, bat: !c.daGhim) } }
                .tint(.orange)
            if c.laNhomBool {
                Button(c.daTatThongBao ? "Bật TB" : "Tắt TB") { Task { await vm.datTatThongBao(c, tat: !c.daTatThongBao) } }
                    .tint(.gray)
            }
        }
    }
}

/// Điểm nhảy tới khi bấm 1 kết quả tìm tin nhắn (cần ts + msgId để mở đúng chỗ, giống moCuoc(id,{quanh,sang})).
struct TimKiemDiem: Hashable { let tin: Tin }

struct ConversationRow: View {
    let c: Cuoc

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(ten: c.ten ?? c.id, anh: c.anh, khoa: c.id, kichThuoc: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text((c.laNhomBool ? "👥 " : "") + (c.ten ?? c.id))
                    .font(.system(size: 16, weight: c.chuaDoc > 0 ? .semibold : .regular))
                    .lineLimit(1)
                Text(dongXemTruoc)
                    .font(.system(size: 14))
                    .foregroundStyle(c.chuaDoc > 0 ? .primary : .secondary)
                    .fontWeight(c.chuaDoc > 0 ? .medium : .regular)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 3) {
                    if c.daTatThongBao { Image(systemName: "bell.slash.fill").font(.caption2) }
                    if c.daGhim { Text("📌").font(.caption2) }
                }
                if let ts = c.tinCuoiTs { Text(DinhDang.gioNgan(ts)).font(.caption).foregroundStyle(.secondary) }
                if c.chuaDoc > 0 {
                    Text(c.chuaDoc > 99 ? "99+" : "\(c.chuaDoc)")
                        .font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.red, in: Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var dongXemTruoc: String {
        guard let t = c.tinCuoi else { return c.laNhomBool ? "Nhóm" : "Chưa có tin lưu" }
        var xem = t.xem ?? ""
        if t.laToi == true { xem = "Bạn: " + xem }
        else if c.laNhomBool, let ten = t.ten, !ten.isEmpty { xem = "\(ten): \(xem)" }
        return xem
    }
}

struct KetQuaTimTinRow: View {
    let t: Tin

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(ten: t.tenCuoc ?? t.cuocId ?? "", anh: nil, khoa: t.cuocId ?? "", kichThuoc: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.tenCuoc ?? t.cuocId ?? "").font(.system(size: 15)).lineLimit(1)
                Text("\(t.laToi ? "Bạn" : (t.tenNguoi ?? "")): \(t.thuHoi ? "(đã thu hồi) " : "")\(t.chu ?? t.tenFile ?? "")")
                    .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(DinhDang.gioNgan(t.ts)).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
