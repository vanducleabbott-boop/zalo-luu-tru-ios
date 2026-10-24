// v5.4: tiện ích Chia sẻ - app hiện trong bảng Chia sẻ của iOS (kèm gợi ý người/nhóm như Zalo).
// Nhận ảnh/video/file/link/chữ từ app khác, chọn người hoặc nhóm rồi gửi thẳng lên máy chủ
// (cùng route với app: /api/gui, /api/tai-len + /api/gui-album).

import UIKit
import SwiftUI
import Intents
import UniformTypeIdentifiers

@objc(ShareViewController)
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let goiY = (extensionContext?.intent as? INSendMessageIntent)?.conversationIdentifier
        let mh = ManHinhChiaSe(mucNhan: (extensionContext?.inputItems as? [NSExtensionItem]) ?? [], cuocGoiY: goiY,
                               xong: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
                               huy: { [weak self] in
                                   self?.extensionContext?.cancelRequest(withError: NSError(domain: "ZaloShare", code: 0))
                               })
        let host = UIHostingController(rootView: mh)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

// ---------------------------------------------------------------- nội dung nhận được
private struct TepChiaSe: Identifiable {
    let id = UUID()
    let url: URL          // bản sao trong thư mục tạm của tiện ích
    let ten: String
    let laAnhVideo: Bool
}

@MainActor
private final class ChiaSeVM: ObservableObject {
    @Published var tep: [TepChiaSe] = []
    @Published var chu = ""
    @Published var dangDoc = true
    @Published var daChon: [String] = []
    @Published var tuKhoa = ""
    @Published var dangGui = false
    @Published var tienDo = ""
    @Published var loi: String?

    let dsNguoiNhan = ChiaSeChung.dsNguoiNhan

    var dsLoc: [NguoiNhanChiaSe] {
        let q = boDau(tuKhoa.trimmingCharacters(in: .whitespaces))
        if q.isEmpty { return dsNguoiNhan }
        return dsNguoiNhan.filter { boDau($0.ten).contains(q) }
    }

    func ten(_ id: String) -> String { dsNguoiNhan.first { $0.id == id }?.ten ?? id }

    func chon(_ id: String) {
        if let i = daChon.firstIndex(of: id) { daChon.remove(at: i) } else { daChon.append(id) }
    }

    // ------------------------------------------------ đọc các mục được chia sẻ
    func doc(_ mucNhan: [NSExtensionItem]) async {
        defer { dangDoc = false }
        let thuMuc = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: thuMuc, withIntermediateDirectories: true)
        var cacDong: [String] = []
        for muc in mucNhan {
            if let s = muc.attributedContentText?.string, !s.isEmpty { cacDong.append(s) }
            for p in muc.attachments ?? [] {
                if let t = await docTep(p, vao: thuMuc) { tep.append(t); continue }
                if p.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let u = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, !u.isFileURL {
                    cacDong.append(u.absoluteString)
                } else if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let s = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    cacDong.append(s)
                }
            }
        }
        // link thường đi kèm cả tiêu đề trang lẫn URL -> bỏ dòng trùng
        var gap = Set<String>()
        chu = cacDong.filter { gap.insert($0).inserted }.joined(separator: "\n")
    }

    private func docTep(_ p: NSItemProvider, vao thuMuc: URL) async -> TepChiaSe? {
        let kieu: UTType
        if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) { kieu = .image }
        else if p.hasItemConformingToTypeIdentifier(UTType.movie.identifier) { kieu = .movie }
        else if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                    || (p.hasItemConformingToTypeIdentifier(UTType.data.identifier)
                        && !p.hasItemConformingToTypeIdentifier(UTType.url.identifier)
                        && !p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)) { kieu = .data }
        else { return nil }
        let goiY = p.suggestedName
        return await withCheckedContinuation { tiep in
            _ = p.loadFileRepresentation(forTypeIdentifier: kieu.identifier) { url, _ in
                guard let url else { tiep.resume(returning: nil); return }
                // file gốc bị xoá ngay khi khối này kết thúc -> chép sang chỗ của mình
                var ten = url.lastPathComponent
                if let goiY, !goiY.isEmpty, (goiY as NSString).pathExtension.isEmpty {
                    ten = goiY + (url.pathExtension.isEmpty ? "" : "." + url.pathExtension)
                } else if let goiY, !goiY.isEmpty { ten = goiY }
                let dich = thuMuc.appendingPathComponent(UUID().uuidString + "_" + ten)
                do { try FileManager.default.copyItem(at: url, to: dich) } catch { tiep.resume(returning: nil); return }
                let ext = (ten as NSString).pathExtension.lowercased()
                let laAnhVideo = kieu != .data || ["jpg", "jpeg", "png", "heic", "gif", "webp", "mp4", "mov"].contains(ext)
                tiep.resume(returning: TepChiaSe(url: dich, ten: ten, laAnhVideo: laAnhVideo))
            }
        }
    }

    // ------------------------------------------------ gửi
    func gui() async -> Bool {
        guard let diaChi = ChiaSeChung.diaChi, let phien = ChiaSeChung.phien else {
            loi = "Chưa có phiên đăng nhập. Mở app Zalo lưu trữ, đăng nhập rồi thử lại."
            return false
        }
        let api = APIChiaSe(goc: diaChi, phien: phien)
        dangGui = true
        defer { dangGui = false }
        let noiDung = chu.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            for (i, cuocId) in daChon.enumerated() {
                let tienTo = daChon.count > 1 ? "(\(i + 1)/\(daChon.count)) " : ""
                let anhVideo = tep.filter(\.laAnhVideo)
                if anhVideo.count > 1 {
                    // nhiều ảnh/video -> 1 album như Zalo
                    var ma: [String] = []
                    for (j, t) in anhVideo.enumerated() {
                        tienDo = tienTo + "Tải lên \(j + 1)/\(anhVideo.count)…"
                        ma.append(try await api.taiLenTam(t))
                    }
                    try await api.guiAlbum(cuoc: cuocId, ma: ma)
                } else if let t = anhVideo.first {
                    tienDo = tienTo + "Đang gửi \(t.ten)…"
                    try await api.guiFile(cuoc: cuocId, t)
                }
                for t in tep where !t.laAnhVideo {
                    tienDo = tienTo + "Đang gửi \(t.ten)…"
                    try await api.guiFile(cuoc: cuocId, t)
                }
                if !noiDung.isEmpty {
                    tienDo = tienTo + "Đang gửi tin nhắn…"
                    try await api.guiChu(cuoc: cuocId, chu: noiDung)
                }
                if let n = dsNguoiNhan.first(where: { $0.id == cuocId }) { ChiaSeChung.baoDaNhan(n) }
            }
            return true
        } catch {
            loi = "Không gửi được: " + error.localizedDescription
            return false
        }
    }
}

// ---------------------------------------------------------------- gọi máy chủ (giống ZaloAPI.goi của app)
private struct APIChiaSe {
    let goc: String
    let phien: String

    private func yeuCau(_ duongDan: String, query: [String: String] = [:]) throws -> URLRequest {
        var g = goc
        while g.hasSuffix("/") { g.removeLast() }
        guard var c = URLComponents(string: g + duongDan) else { throw URLError(.badURL) }
        if !query.isEmpty { c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let u = c.url else { throw URLError(.badURL) }
        var req = URLRequest(url: u, timeoutInterval: 600)
        req.httpMethod = "POST"
        req.setValue("zw=\(phien)", forHTTPHeaderField: "Cookie")
        req.setValue("Bearer \(phien)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func kiem(_ data: Data, _ resp: URLResponse) throws -> Data {
        guard let http = resp as? HTTPURLResponse else { return data }
        if http.statusCode == 401 { throw LoiChiaSe("Hết phiên đăng nhập - mở app đăng nhập lại") }
        if !(200...299).contains(http.statusCode) {
            let loi = (try? JSONDecoder().decode([String: String].self, from: data))?["loi"] ?? ""
            throw LoiChiaSe(loi.isEmpty ? "Lỗi máy chủ (\(http.statusCode))" : loi)
        }
        return data
    }

    private func tenMaHoa(_ t: TepChiaSe) -> String {
        t.ten.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t.ten
    }

    /// Gửi thẳng từ file trên đĩa (không nạp cả video vào RAM - tiện ích bị giới hạn bộ nhớ).
    func guiFile(cuoc: String, _ t: TepChiaSe) async throws {
        var req = try yeuCau("/api/gui", query: ["cuoc": cuoc])
        req.setValue(tenMaHoa(t), forHTTPHeaderField: "X-Ten-File")
        let (data, resp) = try await URLSession.shared.upload(for: req, fromFile: t.url)
        _ = try kiem(data, resp)
    }

    func taiLenTam(_ t: TepChiaSe) async throws -> String {
        struct KQ: Decodable { let ma: String }
        var req = try yeuCau("/api/tai-len")
        req.setValue(tenMaHoa(t), forHTTPHeaderField: "X-Ten-File")
        let (data, resp) = try await URLSession.shared.upload(for: req, fromFile: t.url)
        return try JSONDecoder().decode(KQ.self, from: try kiem(data, resp)).ma
    }

    func guiAlbum(cuoc: String, ma: [String]) async throws {
        var req = try yeuCau("/api/gui-album", query: ["cuoc": cuoc])
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["ma": ma])
        let (data, resp) = try await URLSession.shared.data(for: req)
        _ = try kiem(data, resp)
    }

    func guiChu(cuoc: String, chu: String) async throws {
        var req = try yeuCau("/api/gui", query: ["cuoc": cuoc])
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["chu": chu, "tag": [Any]()])
        let (data, resp) = try await URLSession.shared.data(for: req)
        _ = try kiem(data, resp)
    }
}

private struct LoiChiaSe: LocalizedError {
    let errorDescription: String?
    init(_ s: String) { errorDescription = s }
}

private func boDau(_ s: String) -> String {
    s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi"))
        .replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "D").lowercased()
}

// ---------------------------------------------------------------- giao diện
private struct ManHinhChiaSe: View {
    let mucNhan: [NSExtensionItem]
    let cuocGoiY: String?
    let xong: () -> Void
    let huy: () -> Void
    @StateObject private var vm = ChiaSeVM()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if vm.dangDoc { ProgressView() }
                    ForEach(vm.tep) { t in
                        Label(t.ten, systemImage: t.laAnhVideo ? "photo" : "doc").lineLimit(1)
                    }
                    TextField(vm.tep.isEmpty ? "Tin nhắn" : "Thêm lời nhắn (không bắt buộc)", text: $vm.chu, axis: .vertical)
                        .lineLimit(1...5)
                }
                if !vm.daChon.isEmpty {
                    Section("Gửi tới") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(vm.daChon, id: \.self) { id in
                                    Button { vm.chon(id) } label: {
                                        HStack(spacing: 4) {
                                            Text(vm.ten(id)).lineLimit(1)
                                            Image(systemName: "xmark.circle.fill")
                                        }
                                        .font(.subheadline).padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Color.blue.opacity(0.15), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                Section(ChiaSeChung.appGroup == nil ? "" : "Người & nhóm") {
                    if ChiaSeChung.appGroup == nil {
                        Text("Tiện ích chưa đọc được dữ liệu app (thiếu App Group). Hãy ký lại IPA bằng ESign với chứng chỉ có App Group.")
                            .foregroundStyle(.secondary)
                    } else if vm.dsNguoiNhan.isEmpty {
                        Text("Chưa có danh sách hội thoại. Mở app Zalo lưu trữ 1 lần rồi thử lại.").foregroundStyle(.secondary)
                    }
                    ForEach(vm.dsLoc) { n in
                        Button { vm.chon(n.id) } label: {
                            HStack(spacing: 12) {
                                AnhChuCai(ten: n.ten, laNhom: n.laNhom)
                                Text(n.ten).foregroundStyle(.primary).lineLimit(1)
                                Spacer()
                                Image(systemName: vm.daChon.contains(n.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(vm.daChon.contains(n.id) ? Color.blue : Color.secondary)
                                    .font(.title3)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $vm.tuKhoa, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm người, nhóm")
            .navigationTitle("Gửi qua Zalo lưu trữ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ", action: huy).disabled(vm.dangGui) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.daChon.count > 1 ? "Gửi (\(vm.daChon.count))" : "Gửi") {
                        Task { if await vm.gui() { xong() } }
                    }
                    .bold()
                    .disabled(vm.daChon.isEmpty || vm.dangDoc || vm.dangGui
                              || (vm.tep.isEmpty && vm.chu.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
            .overlay {
                if vm.dangGui {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(vm.tienDo).font(.footnote).multilineTextAlignment(.center)
                    }
                    .padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .alert("Lỗi", isPresented: Binding(get: { vm.loi != nil }, set: { if !$0 { vm.loi = nil } })) {
                Button("Đóng", role: .cancel) {}
            } message: { Text(vm.loi ?? "") }
        }
        .task {
            // bấm vào gợi ý người/nhóm trên bảng Chia sẻ -> chọn sẵn người đó
            if let cuocGoiY, vm.daChon.isEmpty { vm.daChon = [cuocGoiY] }
            await vm.doc(mucNhan)
        }
    }
}

private struct AnhChuCai: View {
    let ten: String
    let laNhom: Bool
    var body: some View {
        let chu = ten.split(separator: " ").suffix(2).compactMap(\.first).map(String.init).joined().uppercased()
        ZStack {
            Circle().fill(laNhom ? Color.orange.opacity(0.8) : Color.blue.opacity(0.8))
            if laNhom { Image(systemName: "person.3.fill").font(.system(size: 14)).foregroundStyle(.white) }
            else { Text(chu.isEmpty ? "?" : chu).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white) }
        }
        .frame(width: 36, height: 36)
    }
}
