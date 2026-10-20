// Xem ảnh toàn màn hình (v4.4, 20/10/2026) - như Zalo:
// - Vuốt trái/phải xem lần lượt mọi ảnh của cuộc trò chuyện theo thứ tự gửi (cũ bên trái, mới bên phải).
// - Dải ảnh nhỏ 1 dòng ở dưới để lướt chọn nhanh; ảnh đang xem có viền.
// - Nút Đóng / Chia sẻ / Tải xuống nằm trên THANH RIÊNG phía trên, không đè lên ảnh.
// - Phóng to: chụm 2 ngón / chạm đúp; đang phóng to thì kéo để di chuyển (không lật trang).
// Chia sẻ gửi FILE ảnh (trước gửi link /media kèm mã đăng nhập zw= -> ai có link vào được kho).

import SwiftUI
import Photos

struct ImageViewerView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let anh: AnhXemToan
    var cuocId: String? = nil

    @State private var ds: [Tin] = []          // cũ -> mới
    @State private var chon: String = ""       // msgId đang xem
    @State private var truoc: Int64? = nil     // mốc phân trang ảnh cũ hơn
    @State private var hetCu = false
    @State private var dangTaiCu = false
    @State private var thongBao: String?
    @State private var dangXuLy = false
    @State private var chiaSe: [Any]?

    private var ma: String { chon.isEmpty ? anh.msgId : chon }

    var body: some View {
        VStack(spacing: 0) {
            thanhTren
            ZStack {
                if ds.isEmpty {
                    TrangAnh(url: anh.url)
                } else {
                    TabView(selection: $chon) {
                        ForEach(ds) { t in
                            TrangAnh(url: diaChi(t)).tag(t.msgId)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
                if let thongBao {
                    Text(thongBao).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.black.opacity(0.75), in: Capsule())
                        .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 12)
                        .transition(.opacity)
                }
            }
            if ds.count > 1 { dayAnhNho }
        }
        .background(Color.black.ignoresSafeArea())
        .task { await taiDanhSach() }
        .onChange(of: chon) { moi in
            if let i = ds.firstIndex(where: { $0.msgId == moi }), i < 3 { Task { await taiCuHon() } }
        }
        .sheet(isPresented: Binding(get: { chiaSe != nil }, set: { if !$0 { chiaSe = nil } })) {
            if let chiaSe { BangChiaSe(muc: chiaSe) }
        }
    }

    // ---------------------------------------------------------------- thanh nút trên (ngoài ảnh)
    private var thanhTren: some View {
        HStack(spacing: 14) {
            nut("xmark", nhan: "Đóng") { dismiss() }
            Spacer()
            if let i = ds.firstIndex(where: { $0.msgId == ma }) {
                Text("\(i + 1)/\(ds.count)\(hetCu ? "" : "+")").font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            nut("square.and.arrow.up", nhan: "Chia sẻ") { Task { await chiaSeAnh() } }
            nut("arrow.down.to.line", nhan: "Tải xuống") { Task { await taiXuong() } }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.black)
        .disabled(dangXuLy)
    }

    private func nut(_ bieuTuong: String, nhan: String, _ hanhDong: @escaping () -> Void) -> some View {
        Button(action: hanhDong) {
            Image(systemName: bieuTuong).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 40, height: 40).background(.white.opacity(0.15), in: Circle())
        }
        .accessibilityLabel(nhan)
    }

    // ---------------------------------------------------------------- dải ảnh nhỏ (cũ trái, mới phải)
    private var dayAnhNho: some View {
        ScrollViewReader { cuon in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    if !hetCu {
                        ProgressView().tint(.white).frame(width: 40, height: 56)
                            .onAppear { Task { await taiCuHon() } }
                    }
                    ForEach(ds) { t in
                        Button { chon = t.msgId } label: {
                            AnimatedImageView(url: diaChi(t), contentMode: .scaleAspectFill, boGoc: 0)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(t.msgId == ma ? Color.white : .clear, lineWidth: 2))
                                .opacity(t.msgId == ma ? 1 : 0.6)
                        }
                        .buttonStyle(.plain)
                        .id(t.msgId)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
            }
            .frame(height: 72)
            .background(Color.black)
            .onAppear { cuon.scrollTo(ma, anchor: .center) }
            .onChange(of: chon) { moi in withAnimation { cuon.scrollTo(moi, anchor: .center) } }
        }
    }

    private func diaChi(_ t: Tin) -> URL? {
        if t.msgId == anh.msgId { return anh.url }
        return t.file.flatMap { env.api.diaChiMedia($0) }
    }

    // ---------------------------------------------------------------- tải danh sách ảnh của cuộc trò chuyện
    private static let laAnh: (Tin) -> Bool = { ["anh", "gif"].contains($0.kieu) && $0.file != nil && !$0.thuHoi }

    private func taiDanhSach() async {
        guard let cuocId, ds.isEmpty else { return }
        var gom: [Tin] = []       // mới -> cũ
        var moc: Int64? = nil
        var het = false
        // lùi dần tới khi gặp ảnh đang xem (tối đa 40 trang x 60)
        for _ in 0..<40 {
            guard let kq = try? await env.api.layKho(cuoc: cuocId, loai: "anh", truoc: moc), !kq.ds.isEmpty else { het = true; break }
            gom += kq.ds.filter(Self.laAnh)
            moc = kq.ds.last?.ts
            if kq.ds.count < 60 { het = true; break }
            if gom.contains(where: { $0.msgId == anh.msgId }) { break }
        }
        guard gom.contains(where: { $0.msgId == anh.msgId }) else { return }   // không thấy -> giữ chế độ 1 ảnh
        ds = gom.reversed()
        truoc = moc
        hetCu = het
        chon = anh.msgId
    }

    private func taiCuHon() async {
        guard let cuocId, !hetCu, !dangTaiCu, let moc = truoc else { return }
        dangTaiCu = true
        defer { dangTaiCu = false }
        guard let kq = try? await env.api.layKho(cuoc: cuocId, loai: "anh", truoc: moc), !kq.ds.isEmpty else { hetCu = true; return }
        let them = kq.ds.filter(Self.laAnh).filter { m in !ds.contains(where: { $0.msgId == m.msgId }) }
        ds.insert(contentsOf: them.reversed(), at: 0)
        truoc = kq.ds.last?.ts
        if kq.ds.count < 60 { hetCu = true }
    }

    // ---------------------------------------------------------------- tải xuống / chia sẻ (dữ liệu file, không phải link)
    private func duLieuAnh() async -> Data? {
        let url = ds.first(where: { $0.msgId == ma }).flatMap(diaChi) ?? anh.url
        if let d = MediaDiskCache.shared.layDuLieu(cho: url) { return d }
        return try? await URLSession.shared.data(from: url).0
    }

    private func taiXuong() async {
        dangXuLy = true
        defer { dangXuLy = false }
        guard let data = await duLieuAnh() else { return hien("Không tải được ảnh") }
        let quyen = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard quyen == .authorized || quyen == .limited else { return hien("Chưa cho phép lưu vào Ảnh (Cài đặt → Zalo lưu trữ → Ảnh)") }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            hien("Đã lưu vào Ảnh")
        } catch { hien("Lưu thất bại: \(error.localizedDescription)") }
    }

    private func chiaSeAnh() async {
        dangXuLy = true
        defer { dangXuLy = false }
        guard let data = await duLieuAnh() else { return hien("Không tải được ảnh") }
        let duoi = data.starts(with: [0x47, 0x49, 0x46]) ? "gif" : (data.starts(with: [0x89, 0x50]) ? "png" : "jpg")
        let tep = FileManager.default.temporaryDirectory.appendingPathComponent("anh_zalo_\(Int(Date().timeIntervalSince1970)).\(duoi)")
        do { try data.write(to: tep); chiaSe = [tep] } catch { hien("Không chia sẻ được") }
    }

    private func hien(_ chu: String) {
        withAnimation { thongBao = chu }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { if thongBao == chu { thongBao = nil } } }
    }
}

// 1 trang ảnh: tự giữ mức phóng to riêng. Kéo chỉ có tác dụng khi đang phóng to (minimumDistance khổng lồ khi
// chưa phóng to -> không chặn cử chỉ lật trang của TabView).
private struct TrangAnh: View {
    let url: URL?
    @State private var tiLe: CGFloat = 1
    @State private var tiLeKhoa: CGFloat = 1
    @State private var dich = CGSize.zero
    @State private var dichKhoa = CGSize.zero

    var body: some View {
        AnimatedImageView(url: url, contentMode: .scaleAspectFit, boGoc: 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(tiLe)
            .offset(dich)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                MagnificationGesture()
                    .onChanged { gt in tiLe = max(1, min(6, tiLeKhoa * gt)) }
                    .onEnded { _ in tiLeKhoa = tiLe; if tiLe <= 1 { veGoc() } }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: tiLe > 1 ? 0 : 100_000)
                    .onChanged { gt in dich = CGSize(width: dichKhoa.width + gt.translation.width, height: dichKhoa.height + gt.translation.height) }
                    .onEnded { _ in dichKhoa = dich }
            )
            .onTapGesture(count: 2) {
                withAnimation { if tiLe > 1 { veGoc() } else { tiLe = 2.5; tiLeKhoa = 2.5 } }
            }
            .onDisappear { veGoc() }
    }

    private func veGoc() { tiLe = 1; tiLeKhoa = 1; dich = .zero; dichKhoa = .zero }
}

private struct BangChiaSe: UIViewControllerRepresentable {
    let muc: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: muc, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
