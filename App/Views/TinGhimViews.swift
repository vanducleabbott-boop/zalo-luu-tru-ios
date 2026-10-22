import SwiftUI

// MARK: - Banner hiển thị tin nhắn ghim trên đầu khung chat
struct ThanhTinGhimView: View {
    let dsGhim: [TinGhim]
    let onNhayToi: (String) -> Void
    let onXemTatCa: () -> Void

    private var tinMoiNhat: TinGhim? {
        dsGhim.first
    }

    private var tieuDeText: String {
        guard let g = tinMoiNhat else { return "" }
        if let t = g.tieuDe, !t.isEmpty { return t }
        return "[Tin nhắn]"
    }

    private var nguoiText: String {
        guard let n = tinMoiNhat?.nguoiGhim, !n.isEmpty else { return "" }
        return "• " + n
    }

    private var labelGhim: String {
        if dsGhim.count > 1 {
            return "Tin nhắn ghim (\(dsGhim.count))"
        }
        return "Tin nhắn ghim"
    }

    var body: some View {
        if let g = tinMoiNhat {
            HStack(spacing: 10) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.orange)
                    .rotationEffect(.degrees(45))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(labelGhim)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)

                        if !nguoiText.isEmpty {
                            Text(nguoiText)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    Text(tieuDeText)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if dsGhim.count > 1 {
                    Button(action: onXemTatCa) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(6)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(UIColor.secondarySystemBackground))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.gray.opacity(0.2)),
                alignment: .bottom
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onNhayToi(g.msgId)
            }
        }
    }
}

// MARK: - Sheet danh sách tất cả tin nhắn ghim trong hội thoại
struct DanhSachTinGhimSheet: View {
    let dsGhim: [TinGhim]
    let onChon: (String) -> Void
    let onBoGhim: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(dsGhim) { g in
                    GhimDongRow(g: g, onChon: onChon, onBoGhim: onBoGhim)
                }
            }
            .navigationTitle("Tin nhắn ghim (\(dsGhim.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct GhimDongRow: View {
    let g: TinGhim
    let onChon: (String) -> Void
    let onBoGhim: (String) -> Void

    private var hienThiTieuDe: String {
        if let t = g.tieuDe, !t.isEmpty { return t }
        return "[Tin nhắn]"
    }

    var body: some View {
        Button(action: {
            onChon(g.msgId)
        }) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
                    .rotationEffect(.degrees(45))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    if let nguoi = g.nguoiGhim, !nguoi.isEmpty {
                        Text(nguoi)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }

                    Text(hienThiTieuDe)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .lineLimit(3)
                }

                Spacer()

                Button(action: {
                    onBoGhim(g.msgId)
                }) {
                    Image(systemName: "pin.slash")
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .padding(6)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .padding(.vertical, 4)
        }
    }
}
