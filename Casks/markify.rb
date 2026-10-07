cask "markify" do
  arch arm: "as", intel: "intel"

  version "2.2.1"
  sha256 arm:   "971fc0c705baf40870123c3adfe82933ca6028571edbcf43e5c025204a1e4ed6",
         intel: "2d5591f38909991a3138ad9fdf1f9f12271ecf8132b468a9de8d28048cf76f49"

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
