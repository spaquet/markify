---
name: deploy
description: Release a new Markify version end to end — ask for the version and build, make sure Sparkle signing is set up, bump and tag, watch the release workflow, check the published DMGs and Sparkle feed, then update the website. Use when the user asks to deploy, release, ship or publish a new version.
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

Also ask whether they want hand-written release notes. Sparkle shows the release body as Markdown in the update window. If yes, have them write it (or draft it from `git log <last tag>..main --oneline` for them to approve) and save it as a draft in step 5; otherwise the workflow uses GitHub's generated notes.

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

## 4. Bump, commit, push

Replace only the Markify target's values (both Debug and Release lines):

```bash
sed -i '' -e "s/CURRENT_PROJECT_VERSION = $OLD_BUILD;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/" \
          -e "s/MARKETING_VERSION = $OLD_VERSION;/MARKETING_VERSION = $NEW_VERSION;/" Markify.xcodeproj/project.pbxproj
git diff --stat   # project.pbxproj: 4 lines, plus Info.plist if step 3 changed it
```

Build once to make sure it compiles (`xcodebuild -quiet -project Markify.xcodeproj -scheme Markify -configuration Release build`). Commit as `Markify <version> (<build>)` and push to main. The website is not touched yet.

## 5. Tag and release

If there are hand-written notes: `gh release create v<version> --draft --target main --title "Markify <version>" --notes-file <notes>`. Never publish the release by hand; the workflow publishes it after attaching the assets.

```bash
git tag -a v<version> -m "Markify <version>"
git push origin v<version>
gh run list --workflow release-dmg.yml --limit 1          # the run for the tag
gh run watch <run id> --exit-status --interval 30         # run in the background; about 10 minutes
```

If the run fails, show the failing step's log (`gh run view <id> --log-failed | tail -50`) and stop. Common causes: `SPARKLE_PRIVATE_KEY` missing, or the signature not matching `SUPublicEDKey` (step 3). A published release is immutable; fixing a failure after publishing means a new patch version.

## 6. Check the release

```bash
scripts/check-release.sh v<version> <build>
```

It checks the six assets, that the tag is Latest, that the live appcast names this version and build, and that the update archive verifies against `SUPublicEDKey`, has a valid code signature and holds the right build. Don't continue until it passes.

## 7. Update the website

Only now, with the DMGs published:

```bash
scripts/set-website-version.sh <version>
git diff --stat docs/index.html     # the hero line and the download section
```

Commit as `Update website to version <version>` and push to main. The Pages workflow deploys `docs/`; confirm it succeeded (`gh run list --workflow pages.yml --limit 1`) and that https://spaquet.github.io/markify/ shows the new version (`curl -s https://spaquet.github.io/markify/ | grep -o "Version [0-9.]*"`; the CDN can lag a minute).

## 8. Report

Tell the user: the release URL, the checks that passed, the website commit, and anything skipped. Remind them that the private Sparkle key must stay backed up.
