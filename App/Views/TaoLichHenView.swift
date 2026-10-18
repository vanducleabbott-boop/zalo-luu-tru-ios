// Màn hình tạo lịch hẹn / nhắc hẹn giống Zalo:
// - Đặt tiêu đề, chọn emoji, thời gian hẹn (DatePicker), chế độ lặp lại
// - Tuỳ chọn "Hiển thị trên Zalo gốc" (chiaSe: true): tạo nhắc hẹn Zalo chính thức cho cả hai bên / cả nhóm
//   hoặc lịch riêng (chiaSe: false): chỉ lưu trên máy chủ và đồng bộ vào Cloud của tôi để Zalo điện thoại tự nhắc.

import SwiftUI

struct TaoLichHenView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: ChatViewModel

    @State private var tieuDe = ""
    @State private var emojiChon = "⏰"
    @State private var thoiGian = Date().addingTimeInterval(3600) // Mặc định 1 tiếng sau
    @State private var lap = 0
    @State private var chiaSe = true
    @State private var dangTao = false
    @State private var thongBaoLoi: String?

    private let danhSachEmoji = ["⏰", "📅", "💊", "🏥", "📞", "💼", "🎂", "⭐", "🚗", "🛒", "☕", "📝"]
    private let danhSachLap = [
        (0, "Không lặp"),
        (1, "Hằng ngày"),
        (2, "Hằng tuần"),
        (3, "Hằng tháng")
    ]

    private var laSoTay: Bool {
        vm.cuoc.id == "so-tay"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nội dung nhắc hẹn") {
                    HStack(spacing: 12) {
                        Text(emojiChon)
                            .font(.system(size: 32))
                            .frame(width: 44, height: 44)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))

                        TextField("Nhập nội dung nhắc hẹn…", text: $tieuDe, axis: .vertical)
                            .lineLimit(1...3)
                    }

                    // Danh sách chọn nhanh Emoji
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(danhSachEmoji, id: \.self) { em in
                                Button {
                                    emojiChon = em
                                } label: {
                                    Text(em)
                                        .font(.system(size: 20))
                                        .padding(6)
                                        .background(emojiChon == em ? ZaloMau.xanhNhat : Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(emojiChon == em ? ZaloMau.xanh : Color.clear, lineWidth: 1.5)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Thời gian nhắc") {
                    DatePicker("Thời gian", selection: $thoiGian, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, Locale(identifier: "vi_VN"))

                    Picker("Lặp lại", selection: $lap) {
                        ForEach(danhSachLap, id: \.0) { item in
                            Text(item.1).tag(item.0)
                        }
                    }
                }

                Section("Phạm vi hiển thị") {
                    if laSoTay {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(ZaloMau.xanh)
                                .font(.system(size: 18))
                            Text("📒 Sổ tay: Lịch riêng của bạn, tự động đồng bộ vào Cloud của tôi để Zalo điện thoại tự đổ chuông nhắc.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    } else {
                        Toggle(isOn: $chiaSe) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Hiển thị trên Zalo gốc")
                                    .font(.system(size: 15, weight: .medium))
                                Text(chiaSe
                                     ? "Tạo nhắc hẹn chính thức trên Zalo: Cả hai bên / toàn bộ nhóm trên Zalo gốc đều thấy thẻ hẹn và nhận chuông báo của Zalo."
                                     : "Lịch riêng: Chỉ lưu trong hệ thống lưu trữ và đồng bộ vào Cloud của tôi để điện thoại bạn tự nhắc, người khác không thấy.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(ZaloMau.xanh)
                    }
                }

                Section {
                    Button {
                        Task { await taoLich() }
                    } label: {
                        HStack {
                            Spacer()
                            if dangTao {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.trailing, 8)
                            }
                            Text(dangTao ? "Đang tạo lịch…" : "Tạo lịch hẹn")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .background(hopLe && !dangTao ? ZaloMau.xanh : Color(.systemGray4), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .disabled(!hopLe || dangTao)
                }
            }
            .navigationTitle("Tạo lịch hẹn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
            }
            .alert("Không thể tạo lịch hẹn", isPresented: Binding(get: { thongBaoLoi != nil }, set: { if !$0 { thongBaoLoi = nil } })) {
                Button("Đóng", role: .cancel) {}
            } message: {
                Text(thongBaoLoi ?? "")
            }
        }
    }

    private var hopLe: Bool {
        !tieuDe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        thoiGian.timeIntervalSinceNow >= -60
    }

    private func taoLich() async {
        guard hopLe else { return }
        dangTao = true
        defer { dangTao = false }

        do {
            try await vm.taoLichHen(
                tieuDe: tieuDe.trimmingCharacters(in: .whitespacesAndNewlines),
                batDau: thoiGian,
                lap: lap,
                emoji: emojiChon,
                chiaSe: laSoTay ? false : chiaSe
            )
            dismiss()
        } catch {
            thongBaoLoi = error.localizedDescription
        }
    }
}
