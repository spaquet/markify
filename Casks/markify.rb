cask "markify" do
  arch arm: "as", intel: "intel"

  version "2.5.0"
  sha256 arm:   "ddcf8867dd087b8d7dd1ae2eac44af020c8f56ecbb7bf0403768f22c45e7b479",
         intel: "e84e4f1f1167591cc6ea7d148b39babe60d62da780fd9414850edc6ffcd76b76"

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
