// "Ảnh, file, link đã gửi" của 1 cuộc - khớp napKho()/veKho() trong web/index.html.

import SwiftUI

struct MediaGalleryView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let cuocId: String
    @State private var tab = "anh"
    @State private var ds: [Tin] = []
    @State private var het = false
    @State private var dangTai = false
    @State private var anhDangXem: AnhXemToan?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Ảnh/Video").tag("anh")
                    Text("File").tag("file")
                    Text("Link").tag("link")
                }
                .pickerStyle(.segmented).padding(10)

                if ds.isEmpty && !dangTai {
                    Spacer()
                    Text("Chưa có nội dung phù hợp").foregroundStyle(.secondary)
                    Spacer()
                } else if tab == "anh" {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                            ForEach(ds) { t in
                                let u = t.file.flatMap { env.api.diaChiMedia($0) }
                                ZStack {
                                    if let u {
                                        AsyncImage(url: u) { pha in
                                            if case .success(let img) = pha { img.resizable().scaledToFill() } else { Color(.systemGray5) }
                                        }
                                    } else { Color(.systemGray5) }
                                    if t.kieu == "video" { Image(systemName: "play.fill").foregroundStyle(.white) }
                                }
                                .aspectRatio(1, contentMode: .fill).clipped()
                                .onTapGesture { if t.kieu != "video", let u { anhDangXem = AnhXemToan(url: u, msgId: t.msgId) } }
                            }
                        }
                        .padding(3)
                        taiThemNeuGanCuoi
                    }
                } else if tab == "file" {
                    List(ds) { t in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 6).fill(Color.gray).frame(width: 36, height: 42)
                                .overlay(Text(DinhDang.duoiFile(t.tenFile).uppercased().prefix(4)).font(.system(size: 9, weight: .bold)).foregroundStyle(.white))
                            VStack(alignment: .leading) {
                                Text(t.tenFile ?? "Tệp").lineLimit(1)
                                Text("\(DinhDang.kichCo(t.kichThuoc)) · \(DinhDang.gioPhut(t.ts))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                } else {
                    List(ds) { t in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.url ?? "").foregroundStyle(ZaloMau.xanh).lineLimit(1)
                            Text(DinhDang.gioPhut(t.ts)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Ảnh, file, link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Đóng") { dismiss() } } }
            .task { await taiLai() }
            .onChange(of: tab) { _ in Task { await taiLai() } }
            .sheet(item: $anhDangXem) { a in ImageViewerView(anh: a) }
        }
    }

    @ViewBuilder
    private var taiThemNeuGanCuoi: some View {
        if !het {
            ProgressView().onAppear { Task { await taiThem() } }
        }
    }

    private func taiLai() async {
        ds = []; het = false
        await taiThem()
    }

    private func taiThem() async {
        guard !dangTai, !het else { return }
        dangTai = true
        defer { dangTai = false }
        do {
            let kq = try await env.api.layKho(cuoc: cuocId, loai: tab, truoc: ds.last?.ts)
            ds += kq.ds
            if kq.ds.isEmpty || (tab != "link" && kq.ds.count < 60) { het = true }
        } catch { het = true }
    }
}
