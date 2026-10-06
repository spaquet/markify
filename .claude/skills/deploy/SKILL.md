---
name: deploy
description: Release a new Markify version end to end — ask for the version and build, make sure Sparkle signing is set up, update and rebuild the help, bump and tag, watch the release workflow, check the published DMGs and Sparkle feed, then update the Homebrew cask and the website. Use when the user asks to deploy, release, ship or publish a new version.
disable-model-invocation: true
---

# Deploy a Markify release

Follow the steps in order. Stop and report at the first failure; never update the website for a release that didn't publish. RELEASE.md explains the workflow and why releases are immutable.

## 1. Preflight

```bash
git switch main && git pull --ff-only
git status --short            # must be empty
gh auth status
grep -m2 -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" Markify.xcodeproj/project.pbxproj
gh release list --limit 3
```

The first `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` lines belong to the Markify target (the test targets use 1.0 and 1). Note the current version, build and latest release tag. If the working tree isn't clean or main can't fast-forward, stop and ask.

## 2. Ask for the version and build

Use AskUserQuestion. Offer the next patch and minor versions and the current build + 1, marking a recommendation. Then check the answer:

- The version must be greater than the latest release when compared component by component: 1.6 is *lower* than 1.42. Say so and ask again if it isn't.
- The build must be greater than the current `CURRENT_PROJECT_VERSION`. Sparkle compares builds, not versions, so an installed copy never sees a release with a lower build.
- The tag `v<version>` must not exist yet (`git tag -l v<version>`, `gh release view v<version>`).

Also ask whether they want hand-written release notes. Sparkle shows the release body as Markdown in the update window. If yes, have them write it (or draft it from `git log <last tag>..main --oneline` for them to approve) and save it as a draft in step 6; otherwise the workflow uses GitHub's generated notes.

## 3. Sparkle signing

Updates are signed with an EdDSA key: public half in `SUPublicEDKey` (Markify/Info.plist), private half in the `SPARKLE_PRIVATE_KEY` secret and the login keychain.

```bash
/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Markify/Info.plist
gh secret list | grep SPARKLE_PRIVATE_KEY
```

- If the key is the placeholder `SPARKLE_PUBLIC_KEY` or the secret is missing, ask before running `scripts/setup-sparkle-keys.sh`: it creates a key in the user's keychain and writes a repository secret. Revert any `project.pbxproj` change the script's package resolution leaves (Xcode re-sorts entries); keep the Info.plist change.
- Otherwise check that the keychain key still matches the plist (the tools are in `.build/spm/…` after the script has run once; if missing, run `xcodebuild -resolvePackageDependencies -project Markify.xcodeproj -scheme Markify -clonedSourcePackagesDirPath .build/spm`):

```bash
head -c 100000 /dev/urandom > "$TMPDIR/probe.bin"
SIG=$(.build/spm/artifacts/sparkle/Sparkle/bin/sign_update -p "$TMPDIR/probe.bin")
swift scripts/verify-update-signature.swift "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Markify/Info.plist)" "$SIG" "$TMPDIR/probe.bin"
```

A mismatch means the secret may be stale too: ask, then rerun `scripts/setup-sparkle-keys.sh`. Never replace a key that has shipped without the user's explicit go-ahead: installed copies only accept updates signed with the key they shipped with.

Also check `gh secret list | grep SENTRY_DSN`: a tag build fails without it. If it is missing, stop and point the user to RELEASE.md › Crash Reporting (Sentry); never paste a DSN into the repository.

## 4. Help, tour and website pages

The help is written once in `help/*.md` and built into the app's Help Book (`Markify/Resources/Markify.help`) and the website (`docs/help/`, `docs/faq.html`, `docs/legal.html`, `sitemap.xml`, `robots.txt`, `llms.txt`, `llms-full.txt`). A release must ship help that matches it.

1. List what changed for users since the last release and which help pages cover it:

   ```bash
   git log <last tag>..main --oneline -- Markify MarkifyMarkdown OKFKit
   git diff --stat <last tag>..main -- help Markify/Settings Markify/Shortcuts.swift Markify/ContentView.swift
   ```

   New or changed features, settings, shortcuts, slash-menu entries or menus need their page in `help/` updated (shortcuts.md mirrors `Shortcuts.actions`; formatting.md mirrors `SlashEntry.all`; settings.md mirrors SettingsView). New FAQ-worthy questions go in `help/faq.md` as `###` headings. A new third-party package or bundled resource needs a row in `help/legal.md`, and the About window's “Built with” line in `Markify/AboutView.swift`. Draft the edits, show them to the user, and apply what they approve. If nothing user-visible changed, say so and move on.
2. Rebuild and check:

   ```bash
   scripts/build-help.sh
   scripts/build-help.sh --check   # fails if the Help Book is stale (CI runs this too)
   ```

3. If `Markify/Resources/Welcome.md` (the first-launch tour) changed since the last tag, add the previous version's hash to `MarkifyAppDelegate.previousWelcomes` so untouched copies in users' libraries get the new tour: `git show <last tag>:Markify/Resources/Welcome.md | shasum -a 256`.
4. Commit only what ships in the app: `git add help Markify/Resources/Markify.help Markify/Resources/Welcome.md Markify/MarkifyApp.swift Markify/AboutView.swift` and commit as `Update help for <version>` (skip if there is nothing to commit). Leave the regenerated `docs/` files uncommitted (`git stash push -- docs` if they're in the way): any push under `docs/` redeploys the website, which must wait for the published release in step 9.

## 5. Bump, commit, push

Replace only the Markify target's values (both Debug and Release lines):

```bash
sed -i '' -e "s/CURRENT_PROJECT_VERSION = $OLD_BUILD;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/" \
          -e "s/MARKETING_VERSION = $OLD_VERSION;/MARKETING_VERSION = $NEW_VERSION;/" Markify.xcodeproj/project.pbxproj
git diff --stat   # project.pbxproj: 4 lines, plus Info.plist if step 3 changed it
```

Build once to make sure it compiles (`xcodebuild -quiet -project Markify.xcodeproj -scheme Markify -configuration Release build`). Commit as `Markify <version> (<build>)` and push to main. The website is not touched yet.

## 6. Tag and release

If there are hand-written notes: `gh release create v<version> --draft --target main --title "Markify <version>" --notes-file <notes>`. Never publish the release by hand; the workflow publishes it after attaching the assets.

```bash
git tag -a v<version> -m "Markify <version>"
git push origin v<version>
gh run list --workflow release-dmg.yml --limit 1          # the run for the tag
gh run watch <run id> --exit-status --interval 30         # run in the background; about 10 minutes
```

If the run fails, show the failing step's log (`gh run view <id> --log-failed | tail -50`) and stop. Common causes: `SPARKLE_PRIVATE_KEY` missing, or the signature not matching `SUPublicEDKey` (step 3). A published release is immutable; fixing a failure after publishing means a new patch version.

## 7. Check the release

```bash
scripts/check-release.sh v<version> <build>
```

It checks the six assets, that the tag is Latest, that the live appcast names this version and build, and that the update archive verifies against `SUPublicEDKey`, has a valid code signature and holds the right build. Don't continue until it passes.

## 8. Update the Homebrew cask

`Casks/markify.rb` pins the version and both DMG hashes, so Homebrew users stay on the old release until it changes (HOMEBREW.md). With the release checked:

```bash
scripts/set-cask-version.sh <version>   # downloads both DMGs (slow: run in the background), checks them against the .sha256 files, rewrites version and hashes, runs brew style
git diff Casks                           # version and the two sha256 values only
git commit -m "Update Homebrew cask to <version>" Casks/markify.rb
scripts/set-cask-version.sh --audit     # brew audit --strict --online, both architectures, from a temporary tap of the committed cask
git push
```

If the audit fails, fix the cask, amend the commit and rerun before pushing. Never use `sha256 :no_check` or a `latest/download` URL. Optionally confirm what users get after the push: `brew update && brew info --cask spaquet/markify/markify` (only if the user has the tap).

## 9. Update the website

Only now, with the DMGs published:

```bash
git stash pop    # if step 4 stashed the regenerated docs
scripts/build-help.sh
scripts/set-website-version.sh <version>
git diff --stat docs     # the hero line, download section and softwareVersion in index.html, plus the generated help, FAQ, legal, sitemap and llms.txt
```

Commit everything under `docs/` as `Update website to version <version>` and push to main. The Pages workflow deploys `docs/`; confirm it succeeded (`gh run list --workflow pages.yml --limit 1`) and that https://spaquet.github.io/markify/ shows the new version (`curl -s https://spaquet.github.io/markify/ | grep -o "Version [0-9.]*"`; the CDN can lag a minute).

## 10. Report

Tell the user: the release URL, the checks that passed, the cask commit, the help pages updated (or that none needed it), the website commit, and anything skipped. Remind them that the private Sparkle key must stay backed up.
