cask "markify" do
  arch arm: "as", intel: "intel"

  version "2.5.8"
  sha256 arm:   "ee22c818e7bb9b3921541fe271f568517a72551ef8e3a2e91567b7616f317c9d",
         intel: "bb143b939e723b57b1b25887abdc3ae3baebf2ca7f486c781802b144c828a513"

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
