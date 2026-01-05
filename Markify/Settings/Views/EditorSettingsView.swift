import SwiftUI

struct EditorSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Editor Appearance")
                        .font(.headline)

                    Picker("Font Size:", selection: Binding(
                        get: { FontSize(rawValue: settings.editorFontSize) ?? .medium },
                        set: { settings.editorFontSize = $0.rawValue }
                    )) {
                        ForEach(FontSize.allCases) { size in
                            Text(size.rawValue).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)

                    Picker("Font Family:", selection: Binding(
                        get: { FontFamily(rawValue: settings.editorFontFamily) ?? .monospaced },
                        set: { settings.editorFontFamily = $0.rawValue }
                    )) {
                        ForEach(FontFamily.allCases) { family in
                            Text(family.rawValue).tag(family)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 300)

                    Divider()
                        .padding(.vertical, 8)

                    Text("Startup Behavior")
                        .font(.headline)

                    Toggle("Show editor on launch", isOn: $settings.showEditorOnLaunch)
                }
                .padding()
            }
        }
        .padding(20)
    }
}

#Preview {
    EditorSettingsView()
        .environmentObject(AppSettings.shared)
}
