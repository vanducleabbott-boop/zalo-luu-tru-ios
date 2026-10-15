import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            ConversationListView()
                .tabItem { Label("Tin nhắn", systemImage: "message.fill") }
            ContactsView()
                .tabItem { Label("Danh bạ", systemImage: "person.2.fill") }
            CallPlaceholderView()
                .tabItem { Label("Cuộc gọi", systemImage: "phone.fill") }
            SettingsView()
                .tabItem { Label("Cá nhân", systemImage: "person.crop.circle.fill") }
        }
    }
}
