import AppKit
import SwiftUI

/// The first-run sheet that asks a new user to join the reports program. Joining is the default; Not Now withdraws
/// from it. Either answer is recorded once, and Settings › Privacy changes it later.
struct TelemetryOnboarding: View {
    /// Called once with the user's answer, after the choice is stored.
    let onAnswer: (Bool) -> Void

    @State private var appeared = false
    @State private var pulse = 0

    /// Shown once per launch, so several windows restored at launch don't stack sheets.
    @MainActor static var presentedThisLaunch = false

    private static let points: [(symbol: String, tint: Color, title: String, detail: String)] = [
        ("lock.shield.fill", .teal, "Anonymous by design",
         "Reports carry no name, account or device identifier. Markify collects no IP addresses."),
        ("doc.text.magnifyingglass", .indigo, "Your writing stays yours",
         "No Markdown text, OKF bundle contents, titles, file names or paths ever leave your Mac."),
        ("wrench.and.screwdriver.fill", .orange, "Only technical data",
         "Crash stacks, Markify and macOS versions, your Mac's model, and timing for about one session in ten."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 34)

            VStack(spacing: 10) {
                ForEach(Array(Self.points.enumerated()), id: \.offset) { index, point in
                    pointCard(point)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                        .animation(.spring(duration: 0.55, bounce: 0.25).delay(0.15 + Double(index) * 0.12), value: appeared)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 24)

            Text("You can change your mind anytime in Settings › Privacy.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .padding(.top, 18)

            HStack(spacing: 12) {
                Button("Not Now") { onAnswer(false) }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Button {
                    onAnswer(true)
                } label: {
                    Label("Join the Program", systemImage: "heart.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 6)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .frame(width: 520)
        .background(backdrop)
        .onAppear {
            appeared = true
            pulse += 1
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.pink.opacity(0.35), .clear], center: .center, startRadius: 4, endRadius: 80))
                    .frame(width: 160, height: 160)
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 92, height: 92)
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 7)
                Image(systemName: "heart.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.pink, .white)
                    .symbolEffect(.bounce, value: pulse)
                    .offset(x: 46, y: 40)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
            .accessibilityHidden(true)

            Text("Help make Markify steadier")
                .font(.system(size: 26, weight: .bold, design: .serif))
                .multilineTextAlignment(.center)

            Text("Join the reports program. Crashes and slow spots reach us, so we can fix them faster, and nothing personal comes with them.")
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .padding(.horizontal, 24)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -8)
        .animation(.easeOut(duration: 0.5), value: appeared)
    }

    private func pointCard(_ point: (symbol: String, tint: Color, title: String, detail: String)) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: point.symbol)
                .font(.system(size: 17, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(point.tint)
                .frame(width: 40, height: 40)
                .background(point.tint.opacity(0.14), in: .rect(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(point.title)
                    .font(.system(size: 13.5, weight: .semibold))
                Text(point.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    /// The website's desk colors, faint behind the sheet's material, as in the About window.
    private var backdrop: some View {
        ZStack {
            RadialGradient(colors: [Color.pink.opacity(0.14), .clear], center: UnitPoint(x: 0.5, y: 0.0), startRadius: 0, endRadius: 320)
            RadialGradient(colors: [Color(red: 0.95, green: 0.85, blue: 0.78).opacity(0.3), .clear], center: UnitPoint(x: 0.05, y: 0.9), startRadius: 0, endRadius: 280)
            RadialGradient(colors: [Color(red: 0.78, green: 0.84, blue: 0.95).opacity(0.3), .clear], center: UnitPoint(x: 0.95, y: 0.85), startRadius: 0, endRadius: 300)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
