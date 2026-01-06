import SwiftUI

struct HelpView: View {
    var body: some View {
        TabView {
            // Getting Started Tab
            GettingStartedTab()
                .tabItem {
                    Label("Getting Started", systemImage: "book.fill")
                }
                .tag(0)

            // Features & Shortcuts Tab
            FeaturesShortcutsTab()
                .tabItem {
                    Label("Features", systemImage: "sparkles")
                }
                .tag(1)

            // Tips & Troubleshooting Tab
            TipsTab()
                .tabItem {
                    Label("Tips", systemImage: "lightbulb.fill")
                }
                .tag(2)

            // GitHub Tab
            GitHubTab()
                .tabItem {
                    Label("GitHub", systemImage: "ellipsis.circle")
                }
                .tag(3)
        }
        .frame(height: 400)
    }
}

// MARK: - Getting Started Tab
struct GettingStartedTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader("Getting Started with Markify")

                VStack(alignment: .leading, spacing: 12) {
                    StepItem(number: 1, title: "Open or Create a Document", description: "Use File → New (⌘N) to create a new markdown document, or File → Open (⌘O) to open an existing .md or .mdx file.")

                    StepItem(number: 2, title: "Start Writing", description: "Type your markdown content in the left editor pane. The live preview will appear on the right side in real-time.")

                    StepItem(number: 3, title: "Save Your Work", description: "Press ⌘S to save your document. Markify automatically saves your changes as you type.")

                    StepItem(number: 4, title: "Use Insert Tools", description: "Click buttons in the sidebar to quickly insert images, links, tasks, and lists without typing markdown syntax.")
                }

                Spacer()
            }
            .padding(16)
        }
    }
}

// MARK: - Features & Shortcuts Tab
struct FeaturesShortcutsTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader("Features & Keyboard Shortcuts")

                VStack(alignment: .leading, spacing: 12) {
                    FeatureItem(
                        title: "Live Preview",
                        description: "See your markdown rendered instantly as you type.",
                        shortcut: nil
                    )

                    FeatureItem(
                        title: "Split-Pane Interface",
                        description: "Edit and preview side-by-side for perfect balance.",
                        shortcut: nil
                    )

                    FeatureItem(
                        title: "New Document",
                        description: "Create a new markdown file.",
                        shortcut: "⌘N"
                    )

                    FeatureItem(
                        title: "Open Document",
                        description: "Open an existing .md or .mdx file.",
                        shortcut: "⌘O"
                    )

                    FeatureItem(
                        title: "Save Document",
                        description: "Save your current document.",
                        shortcut: "⌘S"
                    )

                    FeatureItem(
                        title: "Toggle Editor",
                        description: "Show or hide the editor pane to focus on preview or editing.",
                        shortcut: "Eye Icon in Toolbar"
                    )

                    FeatureItem(
                        title: "MDX Support",
                        description: "Full support for JSX components within markdown.",
                        shortcut: nil
                    )

                    FeatureItem(
                        title: "GitHub Flavored Markdown",
                        description: "Tables, strikethrough, task lists, and more.",
                        shortcut: nil
                    )
                }

                Spacer()
            }
            .padding(16)
        }
    }
}

// MARK: - Tips & Troubleshooting Tab
struct TipsTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader("Tips & Troubleshooting")

                VStack(alignment: .leading, spacing: 12) {
                    TipItem(
                        title: "Insert Images Relative to Document",
                        description: "When you insert images, they're automatically saved in an 'images' folder relative to your markdown file. This keeps your project organized."
                    )

                    TipItem(
                        title: "Use Insert Tools for Quick Markdown",
                        description: "Instead of typing markdown syntax, use the sidebar Insert Tools to add images, links, tasks, and lists with a single click."
                    )

                    TipItem(
                        title: "Keyboard Shortcut for Common Tasks",
                        description: "Learn keyboard shortcuts (⌘N, ⌘O, ⌘S) to work faster without reaching for the mouse."
                    )

                    TipItem(
                        title: "Auto-Save Keeps Your Work Safe",
                        description: "Markify automatically saves changes as you type. You can adjust auto-save settings in Preferences."
                    )

                    TipItem(
                        title: "View Recent Files in Sidebar",
                        description: "The sidebar shows your recently edited documents for quick access. Customize how many recent files are shown in Preferences."
                    )

                    TipItem(
                        title: "Markdown Preview Updates in Real-Time",
                        description: "As you type markdown, the preview updates instantly. This helps you verify formatting as you write."
                    )

                    TipItem(
                        title: "Troubleshooting: Preview Not Updating",
                        description: "If the preview isn't updating, check that your markdown syntax is correct. Invalid syntax might prevent rendering."
                    )
                }

                Spacer()
            }
            .padding(16)
        }
    }
}

// MARK: - GitHub Tab
struct GitHubTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader("Contribute & Get Help")

                VStack(alignment: .leading, spacing: 12) {
                    GitHubActionItem(
                        title: "Report a Bug",
                        description: "Found an issue? Open an issue on GitHub to help us improve Markify.",
                        icon: "ladybug.fill",
                        action: {
                            NSWorkspace.shared.open(URL(string: "https://github.com/spaquet/markify/issues")!)
                        }
                    )

                    GitHubActionItem(
                        title: "Request a Feature",
                        description: "Have an idea for a new feature? Create a feature request on GitHub.",
                        icon: "lightbulb.fill",
                        action: {
                            NSWorkspace.shared.open(URL(string: "https://github.com/spaquet/markify/issues")!)
                        }
                    )

                    GitHubActionItem(
                        title: "View Source Code",
                        description: "Markify is open source! Browse the code and see how it works.",
                        icon: "chevron.left.forwardslash.chevron.right",
                        action: {
                            NSWorkspace.shared.open(URL(string: "https://github.com/spaquet/markify")!)
                        }
                    )

                    GitHubActionItem(
                        title: "Star on GitHub",
                        description: "If you like Markify, please give it a star on GitHub!",
                        icon: "star.fill",
                        action: {
                            NSWorkspace.shared.open(URL(string: "https://github.com/spaquet/markify")!)
                        }
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Divider()
                            .padding(.vertical, 4)

                        Text("Having trouble?")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        Text("Check the README for detailed documentation:")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)

                        Link(destination: URL(string: "https://github.com/spaquet/markify#readme")!) {
                            HStack(spacing: 6) {
                                Image(systemName: "book")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("View README")
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

                Spacer()
            }
            .padding(16)
        }
    }
}

// MARK: - Helper Views
struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 16, weight: .bold))
            .padding(.bottom, 4)
    }
}

struct StepItem: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .center) {
                Text("\(number)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor)
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

struct FeatureItem: View {
    let title: String
    let description: String
    let shortcut: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(4)
                }
            }
            Text(description)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

struct TipItem: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(description)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

struct GitHubActionItem: View {
    let title: String
    let description: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                Text(description)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(Color(.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    HelpView()
        .frame(width: 500, height: 400)
}
