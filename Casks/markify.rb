cask "markify" do
  arch arm: "as", intel: "intel"

  version "2.2.0"
  sha256 arm:   "f33bdb5ed03290f5bf354f62182a26ebb32ece0f98b55d2537a582463125c51f",
         intel: "e468750049312521fd5cf9ae1a959ef14dee2f3ef1447e8494f203b7a90ddc69"

  url "https://github.com/spaquet/markify/releases/download/v#{version}/markify-#{arch}.dmg"
  name "Markify"
  desc "Markdown editor with rendered and source lenses"
  homepage "https://spaquet.github.io/markify/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :tahoe

  app "Markify.app"

  caveats <<~EOS
    Markify is ad hoc signed and is not notarized by Apple.
    Homebrew preserves macOS quarantine; Gatekeeper may block first launch.
    If you trust this release, try opening Markify, then use System Settings >
    Privacy & Security > Open Anyway to approve this app individually.
    See https://support.apple.com/102445 for Apple's guidance.
  EOS
end
