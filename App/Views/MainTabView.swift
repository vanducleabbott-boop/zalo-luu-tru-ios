import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        TabView(selection: $env.tabChon) {
            ConversationListView()
                .tabItem { Label("Tin nhắn", systemImage: "message.fill") }
                .tag(0)
            ContactsView()
                .tabItem { Label("Danh bạ", systemImage: "person.2.fill") }
                .tag(1)
            CallPlaceholderView()
                .tabItem { Label("Cuộc gọi", systemImage: "phone.fill") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Cá nhân", systemImage: "person.crop.circle.fill") }
                .tag(3)
        }
    }
}
