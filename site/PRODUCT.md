# Product

<!-- impeccable:product-schema 1 -->

Scope: the Snapwell **marketing site** (`site/`, snapwell.co). The macOS and iOS
apps live in the same repository but are a separate design surface with their
own native design language; this record governs the website only.

## Platform

web

## Stack

Next.js (App Router, Turbopack) + Tailwind v4, deployed as the snapwell.co
marketing site. Fonts via `next/font/google`. Vercel Analytics and an Intercom
widget are already wired in. This is an existing codebase, not a stack choice.

## Users

Primary visitor: **designers and creative professionals** — UI, product, brand,
and motion designers — who build reference libraries. They save screenshots of
interfaces, posters, type specimens, interiors, and video stills, and they
accumulate thousands of them. Their real scene is a full Screenshots folder and
a Figma/Notion/Are.na patchwork where nothing is findable six months later.
They are on macOS, they have strong taste, and they read a landing page's craft
as a proxy for the app's craft.

Secondary, confirmed by product content but not the conversion target: home
renovators organizing project inspiration, and general creative collectors.

## Product Purpose

Snapwell is a native inspiration library for macOS and iOS. You drop in images
and videos; AI analyzes every item automatically and writes searchable
descriptions; you find things later by describing what you saw rather than by
remembering a filename or maintaining folders. Success is a visitor
understanding, in seconds, that the tagging happens *for* them, in the
background, across the whole library.

## Positioning

The mechanism a neighboring product cannot truthfully copy: **automatic,
whole-library AI analysis running in the background on-device-adjacent terms —
your own API key, your own storage, no account, no server, open source.**
Competitors are either cloud services that own your library (Eagle, Are.na,
Pinterest, Milanote) or manual-tagging tools. Snapwell does the tagging work
without taking custody of the collection.

## Operating Context

- Capture happens constantly and carelessly: `Cmd+Shift+4`, share-sheet from
  Safari/Instagram/X, AirDrop, drag from Figma. Filing never happens.
- Retrieval happens under pressure, months later, with only a visual memory
  ("that login screen with the gradient card").
- The library is cross-device: collected on iPhone, worked with on Mac, synced
  over the user's own iCloud.
- Users bring their own AI provider key (OpenAI, Anthropic, Google Gemini, or
  OpenRouter). This is a real setup step, not a hidden detail.

## Capabilities and Constraints

- Import images and videos: drag, paste, web images, iOS Share Extension,
  mobile import queue watched by the Mac app.
- Automatic AI analysis per item, with per-Space custom guidance prompts.
- Content-based search across AI-detected descriptions.
- Spaces: collections with drag-and-drop and per-space export.
- iCloud sync between Mac and iOS; storage is a plain folder in
  `~/Documents/Snapwell/` with sidecar JSON — inspectable, not a black box.
- Free, open source (GitHub), distributed on the App Store for Mac and iOS.
- No subscription, no account, no analytics/telemetry in the apps.
- Requires macOS 15+ / iOS 17+. The iOS target is
  `TARGETED_DEVICE_FAMILY = "1,2"` — iPhone **and** iPad (verified in
  `ios/Snapwell.xcodeproj/project.pbxproj`).
- A silent 12.5s screen recording of the Mac app exists at
  `site/public/video.mp4` (2518×1484, no audio track). It demonstrates the
  library grid and a live search. This is the strongest proof asset the site
  has; the Mac and iOS stories are told as separate beats.

## Brand Commitments

- Name: **Snapwell**. Domain: snapwell.co. App icon exists at
  `site/public/icon.png`.
- Two CTAs, both real: App Store listing and the GitHub repository.
- Voice: plain, unhyped, technically honest. Never salesy.
- **Binding constraint from the user:** the real Mac and iPhone app screenshots
  (`site/public/hero/mac.webp`, `iphone.webp`) must survive any redesign. They
  are the product's strongest asset.
- **Binding negative constraint:** the page must not read as "another
  AI-startup landing page." An outcome that is polished but generic is a
  failure, not a partial success.
- **Standing visual preference (chosen 2026-08-05):** the user deliberately
  took the category standard — the conventional native-Mac-app landing page —
  over an invented visual world. Conventions are to be embraced at full
  fidelity, without irony or smuggled quirk. Craft bar: **Raycast**. Ground is
  **dark** (near-black); the previous gold accent is retired in favour of a
  neutral/cool one. Future work on this surface inherits this commitment
  rather than re-opening it.

## Evidence on Hand

- Real app screenshots: `site/public/hero/mac.webp` (2556×1700, the Mac library
  grid with search field), `site/public/hero/iphone.webp` (963×1701),
  `site/public/hero/background.webp`, `site/public/preview.webp`.
- The Mac screenshot's own content is unusually good raw material: Nike
  typographic posters, UI captures, terminal windows, interiors, video stills,
  AI-generated tag chips ("Typography Posters", "Rounded Cards", "Brand
  Advertising", "Workflow Connector", "Action Buttons") visible on an item.
- Real feature list and privacy statement in the repo root `README.md` and
  `PRIVACY.md`.
- **Absences that must not be fabricated:** no user counts, no testimonials, no
  press, no review quotes, no benchmarks, no pricing tiers, no roadmap dates.
  The product is free; there is nothing to price.

## Product Principles

1. **The collection is the hero.** The product's own material — real images,
   real tags, real search — is more persuasive than any illustration of it.
2. **Show the mechanism, don't assert it.** "AI tags everything" is a claim;
   the tag chips appearing on a real screenshot is proof.
3. **Custody is the differentiator.** Local files, own API key, open source —
   stated as fact, never as fear-marketing.
4. **Craft is the pitch.** The audience is designers; the surface's own
   execution is read as evidence about the app.
5. **Nothing invented.** No fake social proof, no invented numbers. The page
   ships only what is true.

## Accessibility & Inclusion

No product-specific standard established beyond the baseline: the current site
respects `prefers-reduced-motion`, and any replacement must keep doing so.
