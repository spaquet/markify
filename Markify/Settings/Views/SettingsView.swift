import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)

            EditorSettingsView()
                .tabItem {
                    Label("Editor", systemImage: "doc.text")
                }
                .tag(1)

            AutoSaveSettingsView()
                .tabItem {
                    Label("Auto-Save", systemImage: "arrow.clockwise")
                }
                .tag(2)

            SidebarSettingsView()
                .tabItem {
                    Label("Sidebar", systemImage: "sidebar.left")
                }
                .tag(3)
        }
        .frame(width: 500, height: 400)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings.shared)
}
