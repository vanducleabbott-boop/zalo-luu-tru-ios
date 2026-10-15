import SwiftUI

struct LoginView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var matKhau = ""
    @State private var diaChi = ""
    @State private var dangNhap = false
    @State private var loi: String?
    @State private var hienDiaChi = false
    @FocusState private var tapTrungMatKhau: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
                    .frame(width: 88, height: 88)
                    .background(Color(red: 0, green: 0.41, blue: 1), in: Circle())
                Text("Zalo lưu trữ").font(.title2.bold())

                VStack(spacing: 12) {
                    SecureField("Mật khẩu", text: $matKhau)
                        .textContentType(.password)
                        .focused($tapTrungMatKhau)
                        .padding(12)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        .submitLabel(.go)
                        .onSubmit { Task { await dangNhapNgay() } }

                    if let loi { Text(loi).foregroundStyle(.red).font(.footnote) }

                    Button {
                        Task { await dangNhapNgay() }
                    } label: {
                        if dangNhap { ProgressView().frame(maxWidth: .infinity) }
                        else { Text("Vào").bold().frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(matKhau.isEmpty || dangNhap)
                }
                .padding(.horizontal, 32)

                Button(hienDiaChi ? "Ẩn địa chỉ máy chủ" : "Đổi địa chỉ máy chủ") {
                    hienDiaChi.toggle()
                    if hienDiaChi { diaChi = env.settings.diaChiMayChu }
                }
                .font(.footnote)

                if hienDiaChi {
                    VStack(spacing: 8) {
                        TextField("https://...", text: $diaChi)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .padding(10)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        Button("Lưu địa chỉ") { env.doiMayChu(diaChi); hienDiaChi = false }
                            .font(.footnote)
                    }
                    .padding(.horizontal, 32)
                }
                Spacer()
                Spacer()
            }
        }
        .onAppear { tapTrungMatKhau = true }
    }

    private func dangNhapNgay() async {
        loi = nil
        dangNhap = true
        defer { dangNhap = false }
        do {
            let ok = try await env.dangNhap(matKhau: matKhau)
            if !ok { loi = "Sai mật khẩu" }
        } catch { loi = error.localizedDescription }
    }
}
