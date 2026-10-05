cask "markify" do
  arch arm: "as", intel: "intel"

  version "2.0.2"
  sha256 arm:   "acffc0f174ecc9510ed7921cb0f0eb0983d3f2cd5f58fed7f3b829b6aa37c244",
         intel: "58203b94589dc42c0f44f5a6fe2558de1e640ba9dc4e025ebcd806fe5d801879"

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
