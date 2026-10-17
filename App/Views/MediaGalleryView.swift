// "Ảnh, file, link đã gửi" của 1 cuộc trò chuyện.
// Hỗ trợ xem nhanh có bộ đệm (cache), xem ảnh phóng to, phát video, xem file qua QuickLook, mở link Safari,
// và ấn giữ (context menu) để nhảy trực tiếp đến tin nhắn trong đoạn chat.

import SwiftUI
import QuickLook
import AVKit

struct VideoXemToan: Identifiable {
    let url: URL
    let msgId: String
    var id: String { msgId }
}

struct MediaGalleryView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let cuocId: String
    var chonTin: ((Tin) -> Void)? = nil

    @State private var tab = "anh"
    @State private var ds: [Tin] = []
    @State private var het = false
    @State private var dangTai = false
    @State private var anhDangXem: AnhXemToan?
    @State private var videoDangXem: VideoXemToan?
    @State private var fileDangXem: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Ảnh/Video").tag("anh")
                    Text("File").tag("file")
                    Text("Link").tag("link")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if ds.isEmpty && !dangTai {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: iconTabTrong)
                            .font(.system(size: 36))
                            .foregroundStyle(.tertiary)
                        Text("Chưa có nội dung phù hợp")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else if tab == "anh" {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                            ForEach(ds) { t in
                                let u = t.file.flatMap { env.api.diaChiMedia($0) }
                                ZStack {
                                    if let u {
                                        AnimatedImageView(url: u, contentMode: .scaleAspectFill, boGoc: 0)
                                    } else {
                                        Color(.systemGray5)
                                    }

                                    if t.kieu == "video" {
                                        Circle()
                                            .fill(.black.opacity(0.6))
                                            .frame(width: 36, height: 36)
                                            .overlay(Image(systemName: "play.fill").foregroundStyle(.white).font(.system(size: 14)))
                                    } else if t.kieu == "gif" {
                                        Text("GIF")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                                            .padding(4)
                                    }
                                }
                                .aspectRatio(1, contentMode: .fill)
                                .clipped()
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard let u else { return }
                                    if t.kieu == "video" {
                                        videoDangXem = VideoXemToan(url: u, msgId: t.msgId)
                                    } else {
                                        anhDangXem = AnhXemToan(url: u, msgId: t.msgId)
                                    }
                                }
                                .contextMenu {
                                    Button {
                                        denTin(t)
                                    } label: {
                                        Label("Nhảy đến tin nhắn", systemImage: "bubble.left.and.bubble.right.fill")
                                    }
                                    if let u {
                                        if t.kieu == "video" {
                                            Button { videoDangXem = VideoXemToan(url: u, msgId: t.msgId) } label: {
                                                Label("Xem video", systemImage: "play.fill")
                                            }
                                        } else {
                                            Button { anhDangXem = AnhXemToan(url: u, msgId: t.msgId) } label: {
                                                Label("Xem ảnh to", systemImage: "arrow.up.left.and.arrow.down.right")
                                            }
                                        }
                                        ShareLink(item: u) {
                                            Label("Chia sẻ", systemImage: "square.and.arrow.up")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(3)
                        taiThemNeuGanCuoi
                    }
                } else if tab == "file" {
                    List {
                        ForEach(ds) { t in
                            FileGalleryRow(t: t, env: env, fileDangXem: $fileDangXem, denTin: { denTin(t) })
                        }
                        taiThemNeuGanCuoi
                    }
                    .listStyle(.plain)
                } else {
                    List {
                        ForEach(ds) { t in
                            let uStr = t.url ?? ""
                            let linkURL = chuanHoaLink(uStr)
                            Button {
                                if let linkURL { openURL(linkURL) }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(uStr)
                                        .font(.system(size: 15))
                                        .foregroundStyle(ZaloMau.xanh)
                                        .lineLimit(2)
                                    HStack {
                                        Text(DinhDang.gioPhut(t.ts)).font(.caption).foregroundStyle(.secondary)
                                        Spacer()
                                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    denTin(t)
                                } label: {
                                    Label("Nhảy đến tin nhắn", systemImage: "bubble.left.and.bubble.right.fill")
                                }
                                if let linkURL {
                                    Button { openURL(linkURL) } label: {
                                        Label("Mở liên kết", systemImage: "safari")
                                    }
                                }
                                Button {
                                    UIPasteboard.general.string = uStr
                                } label: {
                                    Label("Sao chép liên kết", systemImage: "doc.on.doc")
                                }
                            }
                        }
                        taiThemNeuGanCuoi
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
            .fullScreenCover(item: $videoDangXem) { v in TrinhPhatVideoView(url: v.url) }
            .quickLookPreview($fileDangXem)
        }
    }

    private var iconTabTrong: String {
        switch tab {
        case "file": return "doc.on.doc"
        case "link": return "link"
        default: return "photo.on.rectangle"
        }
    }

    private func chuanHoaLink(_ str: String) -> URL? {
        var s = str.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        return URL(string: s) ?? URL(string: s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
    }

    private func denTin(_ t: Tin) {
        dismiss()
        chonTin?(t)
    }

    @ViewBuilder
    private var taiThemNeuGanCuoi: some View {
        if !het {
            HStack {
                Spacer()
                ProgressView()
                    .padding()
                    .onAppear { Task { await taiThem() } }
                Spacer()
            }
        }
    }

    private func taiLai() async {
        ds = []
        het = false
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

// ---------------------------------------------------------------- Hàng hiển thị File
struct FileGalleryRow: View {
    let t: Tin
    let env: AppEnvironment
    @Binding var fileDangXem: URL?
    let denTin: () -> Void

    @State private var dangTai = false
    @State private var loi: String?

    private var duoi: String { DinhDang.duoiFile(t.tenFile).uppercased() }
    private var mauBieu: Color {
        ["PDF": Color.red, "DOC": .blue, "DOCX": .blue, "XLS": .green, "XLSX": .green, "CSV": .green,
         "PPT": .orange, "PPTX": .orange, "ZIP": .brown, "RAR": .brown][duoi] ?? ZaloMau.chuPhu
    }

    var body: some View {
        Button {
            Task { await moFile() }
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6).fill(mauBieu).frame(width: 40, height: 48)
                    .overlay(Text(duoi.isEmpty ? "FILE" : String(duoi.prefix(4))).font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.tenFile ?? "Tệp").font(.system(size: 15, weight: .medium)).lineLimit(1)
                    Text("\(DinhDang.kichCo(t.kichThuoc)) · \(DinhDang.gioPhut(t.ts))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if dangTai {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                denTin()
            } label: {
                Label("Nhảy đến tin nhắn", systemImage: "bubble.left.and.bubble.right.fill")
            }
            Button {
                Task { await moFile() }
            } label: {
                Label("Mở xem file", systemImage: "doc.viewfinder")
            }
            if let f = t.file, let u = env.api.diaChiMedia(f) {
                ShareLink(item: u) {
                    Label("Chia sẻ file", systemImage: "square.and.arrow.up")
                }
            }
        }
        .alert("Không mở được file", isPresented: Binding(get: { loi != nil }, set: { if !$0 { loi = nil } })) {
            Button("Đóng", role: .cancel) {}
        } message: { Text(loi ?? "") }
    }

    private func moFile() async {
        guard let f = t.file, let url = env.api.diaChiMedia(f) else { return }
        if let cucBo = MediaDiskCache.shared.layFileCucBo(cho: url, tenFile: t.tenFile) {
            fileDangXem = cucBo
            return
        }
        dangTai = true
        defer { dangTai = false }
        if let luu = await MediaDiskCache.shared.taiVaLuuFile(tu: url, tenFile: t.tenFile) {
            fileDangXem = luu
        } else {
            loi = "Không thể tải tệp tin từ máy chủ"
        }
    }
}

// ---------------------------------------------------------------- Trình phát Video toàn màn hình
struct TrinhPhatVideoView: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding()
            }
        }
        .onAppear {
            if let cucBo = MediaDiskCache.shared.layFileCucBo(cho: url) {
                let p = AVPlayer(url: cucBo)
                player = p
                p.play()
            } else {
                let p = AVPlayer(url: url)
                player = p
                p.play()
                Task.detached(priority: .background) {
                    _ = await MediaDiskCache.shared.taiVaLuuVideo(tu: url)
                }
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
