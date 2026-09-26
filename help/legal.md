---
title: Legal
description: Markify's license, privacy statement, and the third-party software, fonts and specifications it uses.
order: 14
keywords: license, legal, privacy, acknowledgements, third party, open source, trademarks, commons clause, mit
web: legal.html
license: true
---
# Legal

## License

Markify is © 2025–2026 Stéphane Paquet. It is distributed under the MIT License with the Commons Clause condition: you may use, study and modify it for personal, educational and other non-commercial purposes, and commercial use needs the author's written permission. The license below is the one published with the [source code on GitHub](https://github.com/spaquet/markify/blob/main/LICENSE), which is the authoritative version.

<div id="license-text" class="license"></div>

## Privacy

Markify doesn't collect, store or share personal data. It has no accounts, no analytics and no advertising. Your documents stay in the files and folders you choose.

Markify connects to the internet only in these cases:

- **Update checks.** Markify downloads its update feed from GitHub (`github.com/spaquet/markify`) to see whether a new version exists, and downloads the update when you install it. This request includes your IP address and Markify's version, as any web request does, and is subject to [GitHub's privacy statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement). Turn automatic checks off in **Settings › General › Updates**.
- **Remote images.** When a document contains an image from a web address and **Settings › General › Load remote images** is on, Markify downloads it from that server. Turn the setting off to stop this.
- **Links you open.** ⌘-clicking a web link opens it in your browser.

**Apple Intelligence** features run on your Mac through Apple's on-device model and system Writing Tools; Markify sends no text to cloud services. Apple's handling of Apple Intelligence is described in [Apple's privacy policy](https://www.apple.com/legal/privacy/).

**This website** is hosted on GitHub Pages, which may log visits as described in GitHub's privacy statement, and loads its typefaces from Google Fonts, which receives your IP address under [Google's privacy policy](https://policies.google.com/privacy). It sets no cookies and uses no analytics.

## Third-party software and specifications

Markify is built on the work of others. Thank you to everyone behind these projects.

### In the app

| Component | Used for | Author | License |
| --- | --- | --- | --- |
| [swift-markdown](https://github.com/swiftlang/swift-markdown) | Parsing Markdown | Apple Inc. and the Swift project | Apache 2.0 |
| [swift-cmark](https://github.com/swiftlang/swift-cmark) (cmark-gfm) | CommonMark and GFM parser | John MacFarlane, GitHub, Apple and contributors | BSD 2-Clause and others |
| [SwaTex](https://github.com/PhraseHQ/SwaTex) | Typesetting math | Phrase and SwaTex contributors | MIT |
| [KaTeX fonts](https://github.com/KaTeX/katex-fonts) | Math typefaces, bundled with SwaTex | The KaTeX authors | SIL Open Font License 1.1 |
| [Mermaid](https://github.com/mermaid-js/mermaid) 12 | Drawing diagrams | Knut Sveidqvist and contributors | MIT, with bundled dependencies under their own licenses |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | Software updates | Andy Matuschak and the Sparkle Project | MIT, with components under BSD and other licenses |
| [Yams](https://github.com/jpsim/Yams) | Reading YAML frontmatter | JP Simard and contributors | MIT |
| [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine) | The design pattern behind the editor's layout-fragment drawing (no code is copied) | nodes-app | Apache 2.0 |

### Specifications and services

| Name | How Markify uses it | Owner |
| --- | --- | --- |
| [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md) (OKF) | Reading and editing knowledge bundles | Google Cloud, Apache 2.0 |
| [CommonMark](https://commonmark.org) and [GitHub Flavored Markdown](https://github.github.com/gfm/) | The Markdown syntax Markify follows | The CommonMark project; GitHub, Inc. |
| Apple Intelligence, Writing Tools and the Foundation Models framework | On-device writing features | Apple Inc. |
| [GitHub](https://github.com) | Source code, releases, update feed and this website | GitHub, Inc. |

### On this website

| Component | Author | License |
| --- | --- | --- |
| [Newsreader](https://fonts.google.com/specimen/Newsreader) typeface | Production Type | SIL Open Font License 1.1 |
| [JetBrains Mono](https://www.jetbrains.com/lp/mono/) typeface | JetBrains | SIL Open Font License 1.1 |

The full license texts ship with each project; the ones bundled in the app are in its Resources folder.

## Trademarks

Apple, Mac, macOS, Apple Intelligence and New York are trademarks of Apple Inc., registered in the U.S. and other countries. GitHub is a trademark of GitHub, Inc. Google Cloud is a trademark of Google LLC. Other names are trademarks of their respective owners. Markify is an independent project and isn't affiliated with or endorsed by Apple, GitHub or Google.

## Disclaimer

Markify is provided “as is”, without warranty of any kind, as stated in its license.
