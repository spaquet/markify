# Releasing Markify

Releases are built by GitHub Actions ([`release-dmg.yml`](.github/workflows/release-dmg.yml)) when you push a version tag. The workflow builds a DMG for Apple silicon, one for Intel and a universal update archive for Sparkle, attaches them and the Sparkle appcast to a draft release, and then publishes it.

> **Why tag first?** This repository has **immutable releases** turned on. Once a release is published, its assets and tag are locked, so nothing can be uploaded to it afterwards (GitHub answers `HTTP 422: Cannot upload assets to an immutable release`). The workflow therefore attaches the DMGs while the release is still a draft and publishes it last. Never publish a release by hand before the workflow has run.

## In-App Updates (Sparkle)

Markify checks for updates with [Sparkle](https://sparkle-project.org). Its feed is `https://github.com/spaquet/markify/releases/latest/download/appcast.xml` (`SUFeedURL` in `Markify/Info.plist`), so it always serves the appcast attached to the latest published release. Settings › General › Updates turns automatic checks and automatic installs on or off; the app menu has **Check for Updates…**.

Each update is signed with an EdDSA key. The public key is `SUPublicEDKey` in `Markify/Info.plist`; the private key is the `SPARKLE_PRIVATE_KEY` repository secret. A tag build fails when the secret is missing, or when the update's signature doesn't verify against `SUPublicEDKey` ([`scripts/verify-update-signature.swift`](scripts/verify-update-signature.swift)), so a placeholder or mismatched key never reaches users.

### One-time key setup

```bash
scripts/setup-sparkle-keys.sh
```

The script creates the key pair in your login keychain (or reuses the one there), writes the public key to `SUPublicEDKey`, and stores the private key as the `SPARKLE_PRIVATE_KEY` secret with `gh`. Commit the `Info.plist` change. Run it again to repair a secret that doesn't match.

Back up the private key (`generate_keys -x <file>`, the tool is in `.build/spm/artifacts/sparkle/Sparkle/bin` after the script runs) somewhere safe: if it is lost, installed copies can no longer accept updates and users must download a new version by hand.

### Signing

CI builds aren't signed with a Developer ID. The workflow signs each app ad hoc after building, because Sparkle rejects an update whose code signature is invalid, and a linker-only signature is. The main app explicitly disables App Sandbox in both Debug and Release, so local images and linked documents need no folder grant. Quick Look remains sandboxed and uses a private, read-only image helper. The release signing step preserves the extension’s sandbox entitlements. Sparkle accepts an ad hoc update from an ad hoc app on its EdDSA signature alone.

Run `bash scripts/check-preview-images.sh` to verify the image helper from a signed, sandboxed extension client without any folder grants. It checks the release signing order and the README's local images as well as Markdown, HTML and SVG image references.

## Crash Reporting (Sentry)

Markify sends crash reports and a sample of performance traces to Sentry. The DSN is not in the repository: the app reads it from the `SentryDSN` Info.plist key, which is filled from the `SENTRY_DSN` build setting ([`Config/Sentry.xcconfig`](Config/Sentry.xcconfig)). A build without a DSN starts no Sentry at all, and tests never report.

Events carry an environment so testing doesn't mix with what users hit:

| Build | Environment |
| --- | --- |
| Debug (running from Xcode) | `development` |
| Release (CI DMGs, Sparkle updates) | `production` |

In Sentry, pick the environment in the filter at the top of Issues or Performance, or add `environment:production` to a search. For an alert that should only fire for users, add the condition "The event's environment is production".

### One-time setup

1. **Get the DSN.** In Sentry, open **Settings › Projects › markify › Client Keys (DSN)**. To replace a DSN that was committed before, click **Generate New Key**, copy the new DSN, then disable (or delete) the old key so builds that still carry it stop reporting.
2. **Store it as a GitHub secret.** On GitHub, open the repository's **Settings › Secrets and variables › Actions › New repository secret**, name it `SENTRY_DSN` and paste the DSN. Or from the repository folder:

   ```bash
   gh secret set SENTRY_DSN
   # paste the DSN, then press Return
   gh secret list | grep SENTRY_DSN
   ```

   The release workflow passes it to `xcodebuild` as `SENTRY_DSN=…`. A tag build fails when the secret is missing, so a release never ships without crash reports; a manual run only warns.
3. **Upload debug symbols.** Release builds ship without symbols, so without their dSYMs Sentry shows Markify's own frames as `<unknown>`. In Sentry, open **Settings › Developer Settings › Organization Tokens** and create a token (Sentry shows it once), then store it as the `SENTRY_AUTH_TOKEN` repository secret:

   ```bash
   gh secret set SENTRY_AUTH_TOKEN
   gh secret list | grep SENTRY_AUTH_TOKEN
   ```

   Each build job uploads its dSYMs with `sentry-cli debug-files upload`. As with the DSN, a tag build fails when the secret is missing and a manual run only warns. The target's **Upload Debug Symbols to Sentry** build phase does the same for local builds when `sentry-cli` is installed and logged in.
4. **Report from local builds (optional).** Copy `Config/Sentry.local.xcconfig.example` to `Config/Sentry.local.xcconfig` (git-ignored) and put the DSN in it. xcconfig files treat `//` as a comment, so write `https:/$()/` for `https://`. Without that file, local builds report nothing.

To check, build Debug with the local file, run the app, and confirm with `/usr/libexec/PlistBuddy -c 'Print :SentryDSN' <path>/Markify.app/Contents/Info.plist` that the DSN is in the bundle; an event from it appears under `development`.

## How to Create a Release

In Claude Code, `/deploy` runs these steps: it asks for the version and build, checks the Sparkle key and the Sentry secrets, updates and rebuilds the help, bumps and tags, watches the workflow, checks the published release and its Sentry dSYM uploads, and then updates the Homebrew cask and the website. The skill is in `.claude/skills/deploy/SKILL.md`. By hand:

### Step 0: Update the help

Update `help/*.md` for anything user-visible in this release, then run `scripts/build-help.sh`. Commit `help/` and `Markify/Resources/Markify.help` (the Help Book ships in the app); leave the regenerated `docs/` files for Step 5, since any push under `docs/` redeploys the website. If `Markify/Resources/Welcome.md` changed, add the previous version's SHA-256 to `MarkifyAppDelegate.previousWelcomes`.

### Step 1: Update the version

1. Open `Markify.xcodeproj`, select the **Markify** target, then the **General** tab.
2. Set **Version** (`MARKETING_VERSION`) to the new version, e.g. `1.27`.
3. Bump **Build** (`CURRENT_PROJECT_VERSION`). It must be higher than the last release's: Sparkle compares builds, not versions.
4. Test the app, then commit and push to `main`. Leave the website for Step 5, once the release is published.

### Step 2 (optional): Prepare the release notes as a draft

If you want hand-written notes, create a **draft** for the tag before pushing it. The workflow reuses the draft and keeps its title and notes:

```bash
gh release create v1.27 --draft --target main --title "Markify 1.27" --notes-file notes.md
```

You can also create the draft on GitHub → Releases → **Draft a new release**. Type the new tag name, write the notes, and click **Save draft**, not Publish.

If there is no draft, the workflow creates one with GitHub's generated notes, titled `Markify <version>`.

### Step 3: Push the tag

Tags use semantic versioning with a `v` prefix (`v1.27`, `v1.27.1`). Tags are annotated, so give them a message:

```bash
git tag -a v1.27 -m "Markify 1.27"
git push origin v1.27
```

### Step 4: The workflow runs

Pushing the tag starts **Build and Release DMG**:

1. **build** (two jobs in parallel, one per architecture): checks out the tag, builds Markify in Release, creates the DMG and its SHA256 checksum, and uploads them as workflow artifacts. One architecture failing doesn't cancel the other.
   A third job builds a universal app, zips it as `markify-update.zip` and signs it with the Sparkle key.
2. **release**: downloads the builds, uses the draft for the tag (or creates one), writes `appcast.xml` with the release notes, attaches the files, and publishes the release as **Latest**. Installed copies see the update as soon as it is published.

⏱️ About 5–10 minutes. Follow it in the **Actions** tab.

### Step 5: Check the release and update the website

```bash
scripts/check-release.sh v1.27 285      # assets, live appcast, update signature
scripts/build-help.sh                   # website help, FAQ, legal, sitemap, llms.txt
scripts/set-website-version.sh 1.27     # hero line, download section and structured data of docs/index.html
```

Commit and push the `docs/` changes to `main`; the Pages workflow deploys it. The download buttons use `releases/latest/download/…`, so they already point to the new DMGs.

Update `Casks/markify.rb` to the published version and both verified DMG SHA-256 hashes with `scripts/set-cask-version.sh <version>`, commit, validate both architecture branches with `scripts/set-cask-version.sh --audit`, and push the cask change to `main`. See [HOMEBREW.md](HOMEBREW.md). Homebrew updates use this pinned cask; publishing a GitHub release alone does not update it.

### Release assets

- `markify-as.dmg` and `markify-as.dmg.sha256` for Apple silicon (M1 and later)
- `markify-intel.dmg` and `markify-intel.dmg.sha256` for Intel Macs
- `markify-update.zip` and `appcast.xml` for Sparkle

The website's download buttons use `https://github.com/spaquet/markify/releases/latest/download/<file>`, so they point to the new release as soon as it is published. Keep the asset names unchanged.

## Testing Without Releasing

Run the workflow by hand to check that both architectures build:

1. GitHub → **Actions** → **Build and Release DMG** → **Run workflow**, on `main` (or any branch).
2. Only the **build** jobs run. The **release** job is skipped because there's no tag.
3. Download `markify-as-v<branch>` and `markify-intel-v<branch>` from the run's **Artifacts** section (kept 90 days), then mount each DMG, drag Markify to Applications and launch it.

From the command line:

```bash
gh workflow run release-dmg.yml --ref main
gh run watch
```

## Release Checklist

- [ ] `MARKETING_VERSION` and build number updated
- [ ] App tested on Apple silicon and, if possible, Intel
- [ ] Changes committed and pushed to `main`
- [ ] (Optional) Draft release with notes saved for the new tag
- [ ] Annotated tag pushed: `git tag -a vX.Y -m "Markify X.Y" && git push origin vX.Y`
- [ ] Build number (`CURRENT_PROJECT_VERSION`) is higher than the last release's; Sparkle compares it, not the version
- [ ] Workflow succeeded and `scripts/check-release.sh` passes
- [ ] Homebrew cask version and both DMG hashes updated, validated and pushed
- [ ] Website updated with `scripts/set-website-version.sh` and deployed

## Verifying Downloaded Files

```bash
cd ~/Downloads
shasum -c markify-as.dmg.sha256
# or
shasum -c markify-intel.dmg.sha256
```

The output should be `markify-as.dmg: OK` or `markify-intel.dmg: OK`.

## Troubleshooting

### "Release vX.Y is already published and immutable"

Someone published the release before the workflow finished. A published immutable release can't receive assets. Either delete that release, or bump the patch version and tag again (for example `v1.26` was published empty and `v1.26.1` replaced it).

### Build failed

Open the failed run in **Actions** and check the **Build Markify** step. The runner uses `macos-latest`, and the **Show Xcode version** step prints the Xcode it used. The project targets macOS 26, so it needs Xcode 26 or later.

### Version not extracted correctly

The version comes from the tag name with the `v` removed (`v1.27` → `1.27`). Use `vX.Y` or `vX.Y.Z`.

### Assets missing from the release

- Check that the **release** job ran and succeeded. It only runs for `v*` tag pushes, not for manual runs.
- Wait for the workflow to finish, then refresh the release page.

## Release History

See the [Releases page](https://github.com/spaquet/markify/releases).

## Future Enhancements

### Code signing and notarization

- Buy an Apple Developer ID certificate
- Sign and notarize in the workflow
- Remove the security warning on first launch
- Keep the main app unsandboxed for direct filesystem access; Developer ID signing and notarization do not require App Sandbox. Keep Quick Look sandboxed.
- The first Developer ID release changes the signing identity; Sparkle accepts it because the EdDSA key stays the same

## Questions?

- [GitHub Issues](https://github.com/spaquet/markify/issues)
- [Workflow file](.github/workflows/release-dmg.yml)
