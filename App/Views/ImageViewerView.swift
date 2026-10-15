// Xem ảnh toàn màn hình + phóng to/kéo (chụm 2 ngón), giống .xem-anh trong web/index.html.

import SwiftUI

struct ImageViewerView: View {
    @Environment(\.dismiss) private var dismiss
    let anh: AnhXemToan
    @State private var ti_le: CGFloat = 1
    @State private var tiLeKhoa: CGFloat = 1
    @State private var dich = CGSize.zero
    @State private var dichKhoa = CGSize.zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AsyncImage(url: anh.url) { pha in
                switch pha {
                case .success(let img):
                    img.resizable().scaledToFit()
                        .scaleEffect(ti_le)
                        .offset(dich)
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { gt in ti_le = max(1, min(6, tiLeKhoa * gt)) }
                                    .onEnded { _ in tiLeKhoa = ti_le; if ti_le <= 1 { withAnimation { dich = .zero; dichKhoa = .zero } } },
                                DragGesture()
                                    .onChanged { gt in if ti_le > 1 { dich = CGSize(width: dichKhoa.width + gt.translation.width, height: dichKhoa.height + gt.translation.height) } }
                                    .onEnded { _ in dichKhoa = dich }
                            )
                        )
                        .onTapGesture(count: 2) {
                            withAnimation { if ti_le > 1 { ti_le = 1; tiLeKhoa = 1; dich = .zero; dichKhoa = .zero } else { ti_le = 2.5; tiLeKhoa = 2.5 } }
                        }
                default:
                    ProgressView().tint(.white)
                }
            }
            VStack {
                HStack {
                    Spacer()
                    ShareLink(item: anh.url) { Image(systemName: "square.and.arrow.up").foregroundStyle(.white).padding(10).background(.white.opacity(0.15), in: Circle()) }
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.white).padding(10).background(.white.opacity(0.15), in: Circle()) }
                }
                .padding()
                Spacer()
            }
        }
    }
}
