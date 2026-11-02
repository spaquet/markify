# Localization

Status of the macOS app's localization: what ships, what is missing, and what comes next. Scope and rules are in [AGENTS.md](AGENTS.md#localization) and [DECISIONS.md](DECISIONS.md). Tracking issue: [#101](https://github.com/spaquet/markify/issues/101).

Last checked: 2026-11-02 on `fix/localization-gaps-2.5.7`, from `main` at `875cf43`.

## Languages

| Language | Locale | Status | Catalog coverage | Issue |
|---|---|---|---|---|
| English | `en` | Development, reference and fallback language | 684 keys (source) | — |
| French | `fr` (France reference, shared worldwide) | Shipped | 683 / 683 | [#102](https://github.com/spaquet/markify/issues/102) |
| Spanish (Spain) | `es-ES` | Shipped | 683 / 683 | [#103](https://github.com/spaquet/markify/issues/103) |
| Italian | `it` | Shipped (2.5.3) | 683 / 683 | [#108](https://github.com/spaquet/markify/issues/108) |
| German | `de` | Shipped | 683 / 683 | [#107](https://github.com/spaquet/markify/issues/107) |
| Portuguese (Portugal) | `pt-PT` | Shipped | 683 / 683 | [#104](https://github.com/spaquet/markify/issues/104) |
| Finnish | `fi` | Shipped (2.5.5) | 683 / 683 | [#109](https://github.com/spaquet/markify/issues/109) |
| Swedish | `sv` | Shipped (2.5.5) | 683 / 683 | [#110](https://github.com/spaquet/markify/issues/110) |
| Norwegian Bokmål | `nb` | Shipped (2.5.5) | 683 / 683 | [#111](https://github.com/spaquet/markify/issues/111) |
| Russian | `ru` | To come | Not started | [#105](https://github.com/spaquet/markify/issues/105) (open) |
| Ukrainian | `uk` | To come | Not started | [#106](https://github.com/spaquet/markify/issues/106) (open) |

Catalog coverage counts keys in `Markify/Localizable.xcstrings` with a translation for that language, out of the keys marked for translation. The key `X` (the name of the X platform) is marked `shouldTranslate: false`, so it is excluded.

## What is localized

- **Catalogs:** `Markify/Localizable.xcstrings` (app UI, menus, settings, dialogs, accessibility text), `Markify/InfoPlist.xcstrings`, `QuickLook/InfoPlist.xcstrings` (one key, six languages) and `PreviewImages/InfoPlist.xcstrings`.
- **Code path:** SwiftUI and Foundation APIs (`String(localized:)`, `LocalizedStringKey`). Stored or compared values stay English; the UI shows them through `String.localizedLabel` (`Markify/Localization.swift`).
- **Plurals:** String Catalog plural variants, one count per string. No `n == 1 ? … : …` in code.
- **Formatting:** platform locale formatting for dates and numbers. Translation language and system region are independent.

## Known gaps

- **Help Book and Welcome tour stay English only** for now (decided 2026-11-02). `Markify/Resources/Markify.help` contains only `en.lproj`, and `Markify/Resources/Welcome.md` is not translated. Do not rename or replace users' existing Welcome notes.
- **Issue #101 checklist is out of date.** Its language list still shows #104 and #107 to #111 as open, although they are closed and shipped. Its branch names also don't match (#104 and #107 both list `localization/german-portuguese`). Update the checklist when the next language is opened.
- **Russian and Ukrainian are not in the project's regions.** `knownRegions` in `Markify.xcodeproj/project.pbxproj` lists `en, Base, fr, es-ES, it, de, pt-PT, sv, fi, nb`. Add `ru` and `uk` in their language branches.

## Process for each new language

Follow [AGENTS.md](AGENTS.md#localization):

1. Open a sub-issue of #101 and create its branch from the shared foundation.
2. Export from Xcode (`.xcloc`/XLIFF), translate with translator comments, and review in context. Agent-generated translations need review.
3. Add the locale to `knownRegions` and the catalog.
4. Test with Xcode's language/region overrides and pseudolocalization. Check clipping in the format bar, settings and sidebar.
5. Keep CLI, skills, plugins, agent integrations and the website in English. Do not translate user documents, Markdown/MDX syntax, CLI command names or persisted identifiers.
6. Record review evidence in the language PR.

Norwegian's written standard was set to Bokmål in #111. Portuguese is European Portuguese (`pt-PT`) only. French is one shared localization.
