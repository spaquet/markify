cask "markify" do
  arch arm: "as", intel: "intel"

  version "2.2.2"
  sha256 arm:   "d13b56e934c852ee58f0fd9f0910adbd2deea19db91f2c8550933d3a3a432116",
         intel: "ec5568a494d1fb3710e5e94af8984327afe5217325ed08215a2713aae7ac0acb"

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
