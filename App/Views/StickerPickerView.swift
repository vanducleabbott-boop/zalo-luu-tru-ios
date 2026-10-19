// Bảng chọn sticker như Zalo (v4.1, 19/10/2026).
// Máy chủ (bot_zalo + sticker_kho.mjs) tải sẵn CẢ BỘ của mọi sticker mình gửi / người khác gửi tới, đổi thành GIF động.
// Hàng trên: các bộ (bộ dùng gần nhất trước, biểu tượng = sticker đầu bộ); dưới: lưới GIF của bộ đang chọn.
// Chạm 1 sticker -> gửi ngay vào hội thoại rồi đóng bảng.

import SwiftUI

struct StickerTrongKho: Decodable, Identifiable, Hashable {
    let id: Int
    let cateId: Int
    let type: Int?
    let file: String
}

struct BoSticker: Decodable, Identifiable {
    let cateId: Int
    let ds: [StickerTrongKho]
    var id: Int { cateId }
}

struct StickerPickerView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dong
    @ObservedObject var vm: ChatViewModel

    @State private var dsBo: [BoSticker] = []
    @State private var boChon: Int?
    @State private var dangTai = true
    @State private var loiTai: String?
    @State private var dangGui = false

    private let cot = [GridItem(.adaptive(minimum: 76), spacing: 10)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if dangTai {
                    ProgressView("Đang tải kho sticker…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loiTai {
                    VStack(spacing: 10) {
                        Text(loiTai).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Thử lại") { Task { await tai() } }
                    }
                    .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if dsBo.isEmpty {
                    Text("Chưa có bộ sticker nào.\nKhi bạn hoặc người khác gửi sticker, cả bộ sẽ được tải về đây.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    hangBo
                    Divider()
                    luoiSticker
                }
            }
            .navigationTitle("Sticker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dong() } }
                if dangGui { ToolbarItem(placement: .confirmationAction) { ProgressView() } }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await tai() }
    }

    // Hàng chọn bộ: mỗi bộ hiện sticker đầu tiên
    private var hangBo: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(dsBo) { bo in
                    Button { boChon = bo.cateId } label: {
                        AnimatedImageView(url: bo.ds.first.flatMap { env.api.diaChiMedia($0.file) }, contentMode: .scaleAspectFit, boGoc: 0)
                            .frame(width: 34, height: 34)
                            .padding(5)
                            .background(boChon == bo.cateId ? Color(.systemGray4) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
    }

    private var luoiSticker: some View {
        ScrollView {
            LazyVGrid(columns: cot, spacing: 10) {
                ForEach(dsBo.first(where: { $0.cateId == boChon })?.ds ?? []) { s in
                    Button { Task { await gui(s) } } label: {
                        AnimatedImageView(url: env.api.diaChiMedia(s.file), contentMode: .scaleAspectFit, boGoc: 0)
                            .frame(width: 76, height: 76)
                    }
                    .buttonStyle(.plain)
                    .disabled(dangGui)
                }
            }
            .padding(10)
        }
    }

    private func tai() async {
        dangTai = true; loiTai = nil
        do {
            dsBo = try await env.api.khoSticker()
            if boChon == nil || !dsBo.contains(where: { $0.cateId == boChon }) { boChon = dsBo.first?.cateId }
        } catch {
            loiTai = "Không tải được kho sticker: " + error.localizedDescription
        }
        dangTai = false
    }

    private func gui(_ s: StickerTrongKho) async {
        dangGui = true
        await vm.guiSticker(s)
        dangGui = false
        if vm.loi == nil { dong() }
    }
}
