import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preview Settings")
                        .font(.headline)

                    Picker("Markdown Theme:", selection: Binding(
                        get: { MarkdownTheme(rawValue: settings.markdownTheme) ?? .github },
                        set: { settings.markdownTheme = $0.rawValue }
                    )) {
                        ForEach(MarkdownTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 300)
                }
                .padding()
            }
        }
        .padding(20)
    }
}

#Preview {
    GeneralSettingsView()
        .environmentObject(AppSettings.shared)
}
