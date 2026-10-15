cask "markify" do
  arch arm: "as", intel: "intel"

  version "2.5.3"
  sha256 arm:   "496de700bd6074416d84115b9baf05b3b0b9d008e82327de1e3ca8f10e38cb49",
         intel: "bcfeea9624e93679a9e2b076136e9ce9b27af10f8403ac81eab8b4afa80c828c"

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
