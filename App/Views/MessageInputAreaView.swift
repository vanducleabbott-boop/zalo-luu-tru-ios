import SwiftUI

struct MessageInputAreaView: View {
    @ObservedObject var vm: ChatViewModel
    @FocusState.Binding var daFocusNhap: Bool
    let onMoLichHen: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let traLoi = vm.traLoi {
                ThanhTraLoiView(t: traLoi) {
                    vm.boTraLoi()
                }
            }
            MessageInputBar(vm: vm, daFocus: $daFocusNhap, onMoLichHen: onMoLichHen)
        }
    }
}
