// Tìm tin nhắn trong 1 cuộc đang mở - khớp timTrongCuoc()/nhayKq() trong web/index.html.

import SwiftUI

struct SearchInConversationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: ChatViewModel
    @State private var tu = ""
    @State private var ketQua: [Tin] = []
    @State private var dangTim = false

    var body: some View {
        NavigationStack {
            List {
                if dangTim { ProgressView() }
                ForEach(ketQua) { t in
                    Button { denTin(t) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(t.laToi ? "Bạn" : (t.tenNguoi ?? "")).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(DinhDang.ngayDai(t.ts) + " " + DinhDang.gioPhut(t.ts)).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(t.thuHoi ? "(đã thu hồi) " + (t.chu ?? "") : (t.chu ?? t.tenFile ?? "")).lineLimit(3)
                        }
                    }
                }
                if ketQua.isEmpty && !tu.isEmpty && !dangTim {
                    Text("Không tìm thấy \"\(tu)\" trong cuộc này").foregroundStyle(.secondary)
                }
            }
            .listStyle(.plain)
            .searchable(text: $tu, prompt: "Nhập từ khoá…")
            .onChange(of: tu) { moi in henTim(moi) }
            .navigationTitle("Tìm tin nhắn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Đóng") { dismiss() } } }
        }
    }

    private func henTim(_ q: String) {
        henCongViecLuu?.cancel()
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { ketQua = []; return }
        henCongViecLuu = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await timNgay(q)
        }
    }

    @State private var henCongViecLuu: Task<Void, Never>?

    private func timNgay(_ q: String) async {
        dangTim = true
        defer { dangTim = false }
        do {
            let kq = try await vm.env.api.timTrongCuoc(cuoc: vm.cuoc.id, q: q)
            guard q == tu else { return }
            ketQua = kq
        } catch {}
    }

    private func denTin(_ t: Tin) {
        dismiss()
        Task { await vm.taiLan1(quanh: t.ts, sangMsgId: t.msgId) }
    }
}
