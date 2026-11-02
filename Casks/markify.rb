cask "markify" do
  arch arm: "as", intel: "intel"

  version "2.5.7"
  sha256 arm:   "dbbb254ea12482f2a67f6bf80d0c61d62137346608011e521f978d61c7edf164",
         intel: "36814769192bf06da16fb32feab98e428bfb6b5164f021ec7eaf2ac56a6763bc"

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
