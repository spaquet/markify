# Releasing Markify

This document describes how to create a new release of Markify with automated DMG creation.

## How to Create a Release

### Step 1: Update the Version in Xcode

1. Open `Markify.xcodeproj`
2. Select the Markify target
3. Go to Build Settings
4. Find `MARKETING_VERSION` and update it to your new version (e.g., `1.1`)
5. Test the app thoroughly to ensure everything works correctly

### Step 2: Commit and Create a Tag

Push your changes and create a version tag:

```bash
git push origin main
git tag v1.1
git push origin v1.1
```

**Tag format**: Use semantic versioning with a `v` prefix (e.g., `v1.0`, `v1.1`, `v2.0`)

### Step 3: Create GitHub Release

1. Go to GitHub → [Releases](https://github.com/spaquet/markify/releases)
2. Click **"Create new release"** (or **"Draft a new release"**)
3. Select the tag you just created (e.g., `v1.1`) from the dropdown
4. Add a descriptive title (e.g., "Markify 1.1")
5. Write detailed release notes describing:
   - New features
   - Bug fixes
   - Improvements
   - Any breaking changes
6. Click **"Publish release"**

### Step 4: Workflow Runs Automatically

Once you publish the release, GitHub Actions automatically:

1. **Checks out your code** at the tagged version
2. **Builds both architectures**:
   - Apple Silicon (arm64)
   - Intel (x86_64)
3. **Creates DMG installers** with professional UI
4. **Generates SHA256 checksums** for verification
5. **Uploads all files** to your GitHub Release as assets

⏱️ **Estimated time**: 5-10 minutes depending on build time

### Release Assets Created

After the workflow completes, your release will have these assets:

- **`markify-as.dmg`** - Apple Silicon (M1/M2/M3/M4 Macs)
- **`markify-as.dmg.sha256`** - Checksum for Apple Silicon DMG
- **`markify-intel.dmg`** - Intel Macs
- **`markify-intel.dmg.sha256`** - Checksum for Intel DMG

Users can download the appropriate DMG for their Mac architecture from the release page.

## Testing Before Production

Before creating a real release, you can test the workflow manually without publishing a release:

### Manual Workflow Test

1. Go to GitHub → **Actions** tab
2. Click **"Build and Release DMG"** workflow in the left sidebar
3. Click **"Run workflow"** button
4. Select your desired branch (usually `main`)
5. Click **"Run workflow"**

The workflow will:
- Build both DMG files
- Generate checksums
- Save them as artifacts (available for 90 days)

### View Test Results

- Check the workflow run in the **Actions** tab
- Download test artifacts to verify they work correctly:
  1. Click the completed workflow run
  2. Scroll to "Artifacts" section
  3. Download `markify-as-v{version}` and `markify-intel-v{version}` artifacts
4. Test both DMGs on the appropriate Mac architectures:
   - Mount the DMG
   - Drag app to Applications folder
   - Launch and verify functionality

## Release Checklist

Before publishing a release, ensure:

- [ ] Version number updated in Xcode (`MARKETING_VERSION`)
- [ ] App tested thoroughly on both Intel and Apple Silicon (if possible)
- [ ] All new features working correctly
- [ ] No critical bugs in the release candidate
- [ ] Release notes written with:
  - Summary of changes
  - New features (if any)
  - Bug fixes (if any)
  - Known issues (if any)
  - Download instructions (if first release)
- [ ] Git tag created and pushed (`git tag vX.X && git push origin vX.X`)
- [ ] GitHub Release published

## Verifying Downloaded Files

Users can verify the authenticity of downloaded files using the SHA256 checksum:

```bash
# Navigate to the Downloads folder
cd ~/Downloads

# Verify the checksum
shasum -c markify-as.dmg.sha256
# or
shasum -c markify-intel.dmg.sha256
```

Output should show: `markify-as.dmg: OK` or `markify-intel.dmg: OK`

## Troubleshooting

### Workflow Failed to Build

1. Check the **Actions** tab for error messages
2. Common issues:
   - **Build errors**: Review Xcode build settings and dependencies
   - **DMG creation failed**: Ensure the app bundle is valid
   - **Upload failed**: Check that the release exists and permissions are correct

### Version Not Extracted Correctly

- Ensure the tag follows the format: `vX.X` or `vX.X.X`
- The `v` prefix is automatically stripped
- Example: `v1.0` → `1.0`

### DMG Not Appearing on Release

- Check that the workflow completed successfully in the Actions tab
- Verify the release is published (not just a draft)
- Wait 5-10 minutes for the workflow to complete
- Refresh the release page

## Release History

See the [Releases page](https://github.com/spaquet/markify/releases) for all published versions and their download links.

## Future Enhancements

### Planned for Phase 2: Code Signing and Notarization

Once Markify has more users, we plan to:
- Purchase an Apple Developer ID certificate
- Implement code signing in the workflow
- Add notarization for a seamless user experience
- Eliminate the security warning on first launch

### Planned for Phase 3: Auto-Updates

We plan to integrate the Sparkle framework for automatic updates:
- Users receive notifications of new versions
- One-click update within the app
- Automatic background updates (optional)

## Questions?

For issues with releases or the automated workflow, check:
- [GitHub Issues](https://github.com/spaquet/markify/issues)
- [Workflow file](.github/workflows/release-dmg.yml)
