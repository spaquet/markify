import SwiftUI

struct AutoSaveSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Auto-Save Configuration")
                        .font(.headline)

                    Toggle("Enable auto-save", isOn: $settings.autoSaveEnabled)

                    if settings.autoSaveEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Auto-save delay:")
                                Spacer()
                                Text(String(format: "%.1f seconds", settings.autoSaveDelay))
                                    .foregroundColor(.secondary)
                            }

                            Slider(
                                value: $settings.autoSaveDelay,
                                in: 0.5...5.0,
                                step: 0.5
                            ) {
                                Text("Delay")
                            }
                        }
                        .padding(.leading, 20)
                    }

                    Divider()
                        .padding(.vertical, 8)

                    Text("Save Notifications")
                        .font(.headline)

                    Toggle("Show save notifications", isOn: $settings.showSaveNotifications)

                    if settings.showSaveNotifications {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Notification duration:")
                                Spacer()
                                Text(String(format: "%.1f seconds", settings.saveNotificationDuration))
                                    .foregroundColor(.secondary)
                            }

                            Slider(
                                value: $settings.saveNotificationDuration,
                                in: 1.0...5.0,
                                step: 0.5
                            ) {
                                Text("Duration")
                            }
                        }
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
    AutoSaveSettingsView()
        .environmentObject(AppSettings.shared)
}
