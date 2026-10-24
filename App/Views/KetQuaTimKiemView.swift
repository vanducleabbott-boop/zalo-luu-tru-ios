// v5.7/5.8: danh sách kết quả tìm kiếm (chia tab Người & nhóm / Tin nhắn / File) dùng chung cho tab "Tin nhắn" và tab "Nhóm".
// Bấm vào 1 kết quả -> mở chat; quay ra lại màn này thì tự thoát tìm kiếm (về đúng tab đang đứng).

import SwiftUI

struct KetQuaTimKiemView: View {
    @ObservedObject var tim: TimKiemViewModel
    @Environment(\.dismissSearch) private var dismissSearch
    @State private var daMoKetQua = false
    /// v5.8: kết quả chia 3 tab
    @State private var tab = TabTim.nguoi
    @State private var daTuChonTab = false

    enum TabTim: Hashable { case nguoi, tin, file }

    private var soNguoi: Int { tim.ketQuaNhom.count + tim.ketQuaCuoc.count }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: Binding(get: { tab }, set: { tab = $0; daTuChonTab = true })) {
                Text(nhan("Người & nhóm", soNguoi)).tag(TabTim.nguoi)
                Text(nhan("Tin nhắn", tim.ketQuaTin.count)).tag(TabTim.tin)
                Text(nhan("File", tim.ketQuaFile.count)).tag(TabTim.file)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12).padding(.vertical, 6)

            List {
                if tim.dangTim && dangTrong { ProgressView().frame(maxWidth: .infinity) }
                switch tab {
                case .nguoi:
                    ForEach(tim.ketQuaNhom) { nhom in
                        NavigationLink { GroupDetailView(nhomId: nhom.id) } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(nhom.ten).font(.system(size: 16, weight: .semibold))
                                    Text("Nhóm phân loại · \(nhom.dsCuocId.count) đoạn chat").font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: "folder.fill").foregroundStyle(ZaloMau.xanh) }
                        }
                    }
                    ForEach(tim.ketQuaCuoc.prefix(200)) { c in
                        NavigationLink(value: c) { ConversationRow(c: c) }
                    }
                case .tin:
                    ForEach(tim.ketQuaTin.prefix(300)) { t in
                        NavigationLink(value: TimKiemDiem(tin: t)) { KetQuaTimTinRow(t: t) }
                    }
                case .file:
                    ForEach(tim.ketQuaFile.prefix(300)) { t in
                        NavigationLink(value: TimKiemDiem(tin: t)) { KetQuaTimFileRow(t: t) }
                    }
                }
                if dangTrong && !tim.dangTim {
                    Text("Không tìm thấy \"\(tim.tuKhoa)\"").foregroundStyle(.secondary)
                }
            }
            .listStyle(.plain)
        }
        // chưa tự bấm tab mà tab đang xem trống -> nhảy sang tab đầu tiên có kết quả
        .onChange(of: [soNguoi, tim.ketQuaTin.count, tim.ketQuaFile.count]) { _ in tuChonTab() }
        .onChange(of: tim.tuKhoa) { _ in daTuChonTab = false }
        // đang tìm mà màn này bị che (đã mở 1 chat) -> lúc quay lại thì thoát tìm kiếm
        .onDisappear { if tim.dangTimKiem { daMoKetQua = true } }
        .onAppear {
            tuChonTab()
            guard daMoKetQua else { return }
            daMoKetQua = false
            dismissSearch()
            tim.tuKhoa = ""
        }
    }

    private var dangTrong: Bool {
        switch tab {
        case .nguoi: return soNguoi == 0
        case .tin: return tim.ketQuaTin.isEmpty
        case .file: return tim.ketQuaFile.isEmpty
        }
    }

    private func nhan(_ ten: String, _ so: Int) -> String { so > 0 ? "\(ten) (\(so > 99 ? "99+" : String(so)))" : ten }

    private func tuChonTab() {
        guard !daTuChonTab, dangTrong else { return }
        if soNguoi > 0 { tab = .nguoi } else if !tim.ketQuaTin.isEmpty { tab = .tin } else if !tim.ketQuaFile.isEmpty { tab = .file }
    }
}

struct KetQuaTimFileRow: View {
    let t: Tin

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: bieuTuong)
                .font(.system(size: 22))
                .foregroundStyle(ZaloMau.xanh)
                .frame(width: 40, height: 40)
                .background(ZaloMau.xanh.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(t.tenFile ?? "File").font(.system(size: 15)).lineLimit(2)
                Text([t.tenCuoc ?? t.cuocId ?? "", DinhDang.kichCo(t.kichThuoc)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(DinhDang.gioNgan(t.ts)).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var bieuTuong: String {
        switch ((t.tenFile ?? "") as NSString).pathExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "doc", "docx": return "doc.text"
        case "xls", "xlsx", "csv": return "tablecells"
        case "ppt", "pptx": return "rectangle.on.rectangle"
        case "zip", "rar", "7z": return "doc.zipper"
        default: return "doc"
        }
    }
}

extension TimKiemDiem {
    /// Cuộc để mở khi bấm 1 kết quả tin/file (giống moCuoc(id,{quanh,sang}) của web).
    var cuoc: Cuoc {
        Cuoc(id: tin.cuocId ?? "", laNhom: tin.laNhomCuoc ?? 0, ten: tin.tenCuoc, anh: nil, tinCuoiTs: nil, tinCuoi: nil,
             chuaDoc: 0, capNhatLuc: nil, ghim: nil, tatTb: nil)
    }
}
