# Homebrew distribution

Markify's project-owned tap lives in this repository at [`Casks/markify.rb`](Casks/markify.rb). It uses the existing immutable GitHub release DMGs, selecting Apple silicon or Intel with a separate SHA-256 checksum for each. The minimum is macOS 26 (Tahoe); Sparkle provides in-app updates.

This is a third-party tap, maintained by Markify, without Homebrew endorsement. The cask pins the latest published release and is updated after each one (see [Maintain the cask](#maintain-the-cask)); `version` in [`Casks/markify.rb`](Casks/markify.rb) is the release Homebrew installs.

## Install and update

The repository is named `markify`, rather than `homebrew-markify`, so the explicit Git URL is required when adding the tap:

```sh
brew tap spaquet/markify https://github.com/spaquet/markify.git
brew install --cask spaquet/markify/markify
```

The fully qualified cask name identifies the project-owned package. If Homebrew refuses to load an untrusted cask, run `brew trust --cask spaquet/markify/markify` and retry. Trust only the cask when whole-tap trust is unnecessary. Homebrew trust is separate from macOS approving an app's first launch.

Current releases are ad hoc signed, without Developer ID signing or Apple notarization. Homebrew keeps quarantine enabled, so Gatekeeper can block first launch. If you choose to trust the release, attempt to open Markify, then use **System Settings › Privacy & Security › Open Anyway** to approve this app individually. See [Apple's guidance](https://support.apple.com/102445). Installation through Homebrew and a matching checksum do not establish that Apple has checked the app.

Quit Markify before upgrading or uninstalling. If Markify is already installed manually in Applications, Homebrew may refuse to replace it; remove the existing app bundle first, keeping your notes and settings.

```sh
brew update
brew upgrade --cask --greedy spaquet/markify/markify
brew uninstall --cask spaquet/markify/markify
```

`--greedy` includes casks marked `auto_updates`, such as Markify. Uninstall removes the app; the cask has no `zap` stanza and preserves notes and settings.

## Maintain the cask

After publishing each release (and once `scripts/check-release.sh` passes), update `version` and both `sha256` values in the cask, then commit the change to the default branch. `/deploy` does this in its Homebrew step. Keep downloads pinned to `releases/download/v<version>/…`; do not use a moving `latest/download` URL or `sha256 :no_check`.

```sh
scripts/set-cask-version.sh <version>   # downloads both DMGs, checks them against the release's .sha256 files, rewrites version and hashes, runs brew style
git diff Casks                           # version and the two sha256 values only
git commit -m "Update Homebrew cask to <version>" Casks/markify.rb
scripts/set-cask-version.sh --audit     # brew audit --strict --online, both architectures, from a temporary tap of the committed cask
git push
```

By hand: download the release's two DMGs and checksum files using `gh release download <tag> --pattern 'markify-*.dmg*'`. Run `shasum -a 256 -c markify-as.dmg.sha256` and `shasum -a 256 -c markify-intel.dmg.sha256` in the download directory. Put the verified hashes into the cask.

After adding the tap, validate both architecture branches (from a checkout of this repository for the style command):

```sh
brew style Casks/markify.rb
brew audit --cask --strict --online --arch all spaquet/markify/markify
```

On a clean test Mac, add the tap and install/uninstall with the commands above. Verify that the correct DMG is selected, Markify launches after the individual approval, quarantine remains present (`xattr -p com.apple.quarantine /Applications/Markify.app`), and uninstall preserves notes and settings. Test Apple silicon and Intel separately; simulated audits do not prove that the Intel app runs.

An explicit signing audit checks the Gatekeeper policy of the machine running it:

```sh
brew audit --cask --online --only signing spaquet/markify/markify
```

Existing local approvals can make this audit pass even for an unnotarized app. Check on a clean Mac and independently require notarization with `codesign --verify -R=notarized --check-notarization <path>/Markify.app`; today's release fails that requirement. Do not hide failures with an audit exception or installation hook. Keep the notarization caveat until the released artifacts pass notarization and Gatekeeper checks. Do not remove quarantine, disable Gatekeeper or re-sign the downloaded app in the cask.

## Eligibility for the official Homebrew cask repository

Checked against Homebrew's documentation on **2026-10-05**:

- [Acceptable Casks](https://docs.brew.sh/Acceptable-Casks) requires official macOS casks to pass Gatekeeper on a default configuration and support the latest major macOS release. Today's Markify artifacts fail that requirement.
- The [Package Acceptance Policy](https://docs.brew.sh/Package-Acceptance-Policy) permits software outside the official criteria in third-party taps. Its usual GitHub notability threshold is 30 forks, 30 watchers or 75 stars; owner submissions need 90 forks, 90 watchers or 225 stars. Exceptions require review, and acceptance is not guaranteed.
- The [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook) defines the download, checksum, architecture, minimum OS, livecheck and `auto_updates` stanzas. The [tap guide](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap) supports a `Casks` directory and an explicit remote URL, so a second repository is unnecessary.

Before proposing an official cask, obtain a Developer ID Application certificate, sign all nested code correctly with the required hardened runtime and timestamps, notarize and staple the distribution, and publish a new immutable release. Follow [Apple's notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution); validate the app and DMGs with `codesign`, `xcrun stapler validate` and Homebrew's signing audit. Keep the main app unsandboxed and the Quick Look extension sandboxed, as described in [RELEASE.md](RELEASE.md).

Then recheck notability, existing casks and open/closed Homebrew pull requests, run the official [submission checks](https://docs.brew.sh/Adding-Software-to-Homebrew), and disclose AI assistance as requested by Homebrew's contribution guidance. Developer ID/notarization work is a separate release change; this tap does not replace it.
