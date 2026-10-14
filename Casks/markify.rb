cask "markify" do
  arch arm: "as", intel: "intel"

  version "2.5.1"
  sha256 arm:   "07b5ce3ea36b46b5befac4d9d7d01175edfc63bcb7571f5ce59db30ccb2a023a",
         intel: "71d021c35e4c860576c030d70003174d948b8cc7523d802fb23f95ada27f6483"

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
