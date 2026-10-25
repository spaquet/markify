cask "markify" do
  arch arm: "as", intel: "intel"

  version "2.5.6"
  sha256 arm:   "6299681bc34322034ba6c75204462b92a2ecef0389db3ca9a837ff56acc3b174",
         intel: "e37033bcd917b90b1e3b0733b15ac0cda1b5b05e935a567939d9e3f960d85f8e"

  url "https://github.com/spaquet/markify/releases/download/v#{version}/markify-#{arch}.dmg"
  name "Markify"
  desc "Markdown editor with rendered and source lenses"
  homepage "https://spaquet.github.io/markify/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sequoia

  app "Markify.app"

  caveats <<~EOS
    Markify is ad hoc signed and is not notarized by Apple.
    Homebrew preserves macOS quarantine; Gatekeeper may block first launch.
    If you trust this release, try opening Markify, then use System Settings >
    Privacy & Security > Open Anyway to approve this app individually.
    See https://support.apple.com/102445 for Apple's guidance.
  EOS
end
