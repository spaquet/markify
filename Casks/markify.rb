cask "markify" do
  arch arm: "as", intel: "intel"

  version "2.5.2"
  sha256 arm:   "6836f1b760020d2362075d8536fa74622aab5aee1a325af21d357a4ac8be1d76",
         intel: "a18bd01612abca84f09c9f912a6f3489daaaf6e2be01598a27a9a7a964d3582f"

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
