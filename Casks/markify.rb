cask "markify" do
  arch arm: "as", intel: "intel"

  version "2.5.5"
  sha256 arm:   "2552b8bc557803963e9b011a77f762dca4993a265b287ff890f12b6d80f60dd6",
         intel: "e08b6ed674ed3806bb8f16a39a22521cf17a8f8c66d68857b72eef3e0e38c91b"

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
