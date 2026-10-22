cask "markify" do
  arch arm: "as", intel: "intel"

  version "2.5.4"
  sha256 arm:   "9ff35f5683a7fca0dcb3f4a1caec0fe247b4fe283f74fdb396947c4570c21cea",
         intel: "f69ec33d4d79d78225d864bcea51767ed86e8e00959388109f1ed899736851bf"

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
