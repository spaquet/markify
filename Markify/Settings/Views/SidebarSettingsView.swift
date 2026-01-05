import SwiftUI

struct SidebarSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Files")
                        .font(.headline)

                    Toggle("Show recent files section", isOn: $settings.showRecentFiles)

                    if settings.showRecentFiles {
                        Picker("Number of recent files:", selection: $settings.recentFilesCount) {
                            Text("3").tag(3)
                            Text("5").tag(5)
                            Text("10").tag(10)
                            Text("15").tag(15)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 300)
                        .padding(.leading, 20)
                    }
                }
                .padding()
            }
        }
        .padding(20)
    }
}

#Preview {
    SidebarSettingsView()
        .environmentObject(AppSettings.shared)
}
