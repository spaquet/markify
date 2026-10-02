import AppKit
import SwiftUI

/// Markify › About Markify: the app, its version, where it lives on the web, and whose work it builds on.
/// The full credits and license are the Legal page of the help, the same page the website shows.
struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? "Version \(short)" : "Version \(short) (\(build))"
    }

    private static let links: [(title: String, symbol: String, address: String)] = [
        ("Website", "globe", "https://spaquet.github.io/markify/"),
        ("GitHub", "chevron.left.forwardslash.chevron.right", "https://github.com/spaquet/markify"),
        ("Releases", "sparkles", "https://github.com/spaquet/markify/releases"),
        ("Sponsor", "heart", "https://github.com/sponsors/spaquet"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 104, height: 104)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                .accessibilityHidden(true)
                .padding(.top, 34)

            Text("Markify")
                .font(.system(size: 30, weight: .bold, design: .serif))
                .padding(.top, 14)
            Text("One page. Two lenses.")
                .font(.system(size: 15, design: .serif).italic())
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            Text(version)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 10)

            HStack(spacing: 8) {
                ForEach(Self.links, id: \.title) { link in
                    Link(destination: URL(string: link.address)!) {
                        VStack(spacing: 5) {
                            Image(systemName: link.symbol)
                                .font(.system(size: 15, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(link.title == "Sponsor" ? Color.pink : Color.accentColor)
                                .frame(height: 18)
                            Text(link.title).font(.system(size: 11, weight: .medium)).foregroundStyle(.primary)
                        }
                        .frame(width: 76, height: 58)
                        .contentShape(.rect(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                    .help(link.address)
                    .accessibilityLabel(link.title)
                    .accessibilityHint("Opens \(link.address) in your browser")
                }
            }
            .padding(.top, 24)

            VStack(spacing: 6) {
                Text("Built with swift-markdown, cmark-gfm, SwaTex, KaTeX fonts, Mermaid, Sparkle, Sentry and Yams. Reads Google Cloud's Open Knowledge Format.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Acknowledgements & License") { HelpBook.open("legal") }
                    .buttonStyle(.link)
            }
            .font(.system(size: 11.5))
            .padding(.horizontal, 30)
            .padding(.top, 22)

            Spacer(minLength: 16)

            Text("© 2025–2026 Stéphane Paquet · Free to use")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .frame(width: 400, height: 470)
        .background {
            // The website's desk colors, faint behind the window's material.
            ZStack {
                RadialGradient(colors: [Color(red: 0.95, green: 0.85, blue: 0.78).opacity(0.35), .clear], center: UnitPoint(x: 0.15, y: 0.1), startRadius: 0, endRadius: 260)
                RadialGradient(colors: [Color(red: 0.78, green: 0.84, blue: 0.95).opacity(0.35), .clear], center: UnitPoint(x: 0.9, y: 0.2), startRadius: 0, endRadius: 280)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}

/// Replaces the standard About panel with `AboutView`.
struct AboutButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About Markify") { openWindow(id: "about") }
    }
}
