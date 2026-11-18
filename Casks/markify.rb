cask "markify" do
  arch arm: "as", intel: "intel"

  version "2.5.9"
  sha256 arm:   "d5fdad5c8f63530730aa0bb80955d94d0990f0c1e6c1022401b8c554444eef83",
         intel: "d13d369c84f29605ed5fb4c2b4c49aac7eb0271fd8665c48743c9de10f6f1822"

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
