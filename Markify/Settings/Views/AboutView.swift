import SwiftUI

struct AboutView: View {
    private var appVersionAndBuild: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "Version \(version) (Build \(build))"
    }

    private var copyright: String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        return "© \(year) Stéphane PAQUET"
    }

    private var websiteURL: URL {
        URL(string: "https://spaquet.github.io/markify/")!
    }

    private var githubURL: URL {
        URL(string: "https://github.com/spaquet/markify")!
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            HStack(alignment: .top, spacing: 16) {
                // Left column: App Icon
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .cornerRadius(14)

                // Right column: App info
                VStack(alignment: .leading, spacing: 8) {
                    // App Name and Version
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Markify")
                            .font(.system(size: 18, weight: .bold, design: .default))

                        Text(appVersionAndBuild)
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundColor(.secondary)
                    }

                    // Developer
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Created by")
                            .font(.system(size: 11, weight: .regular, design: .default))
                            .foregroundColor(.secondary)
                        Text("Stéphane PAQUET")
                            .font(.system(size: 12, weight: .semibold, design: .default))
                    }

                    Spacer()
                        .frame(height: 4)

                    // Links
                    VStack(alignment: .leading, spacing: 6) {
                        Link(destination: websiteURL) {
                            HStack(spacing: 6) {
                                Image(systemName: "globe")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Website")
                                    .font(.system(size: 12, weight: .medium))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Link(destination: githubURL) {
                            HStack(spacing: 6) {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("GitHub")
                                    .font(.system(size: 12, weight: .medium))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(16)

            Divider()
                .padding(.horizontal, 16)

            // Footer
            VStack(spacing: 4) {
                Text("A beautiful, minimal markdown editor for macOS")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundColor(.secondary)

                Text(copyright)
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 12)
        }
    }
}

#Preview {
    AboutView()
        .frame(minWidth: 500, minHeight: 500)
}
