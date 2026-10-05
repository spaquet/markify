<!-- Install and update — Markify Help. Web page: https://spaquet.github.io/markify/help/updates.html -->

# Install and update

## System requirements

Markify needs **macOS 26 Tahoe** or later. There are two downloads: one for Macs with **Apple silicon** (M1 and later) and one for **Intel** Macs. Apple Intelligence features need Apple silicon.

## Installing

1. Download the disk image for your Mac from the [Markify website](https://spaquet.github.io/markify/#download) or the [GitHub releases page](https://github.com/spaquet/markify/releases/latest).
2. Open the downloaded `.dmg` file and drag **Markify** to the **Applications** folder.
3. Eject the disk image.

### Opening Markify the first time

Markify isn't notarized by Apple yet, so the first time you open it macOS says it can't verify the app. To open it:

1. Open Markify from Applications, then click **Done** in the message.
2. Open **System Settings › Privacy & Security**.
3. Scroll to **Security**, find the message about Markify and click **Open Anyway**, then confirm with your password or Touch ID.

You only need to do this once; updates open normally.

## Updating

Markify checks for updates once a day and tells you when a new version is ready. To check now, choose **Markify › Check for Updates…**. Updates are signed, and Markify installs only updates signed by its developer.

In **Settings › General › Updates**, turn automatic checks off, or let Markify download updates and install them when you quit.

## Uninstalling

Drag Markify from Applications to the Trash. Your documents stay where you saved them. To remove its settings too, delete `~/Library/Containers/com.stephanepaquet.Markify` and `~/Library/Preferences/com.stephanepaquet.Markify.plist` if they exist.
