---
name: Snapwell Site
description: The near-black canon — a native-Mac-app landing page where the only colour is the collected work itself.
colors:
  background: "#09090b"
  surface: "#131316"
  border: "#232329"
  border-strong: "#34343c"
  border-hover: "#45454f"
  foreground: "#f4f4f6"
  muted: "#9c9ca6"
  accent: "#b7b2ce"
  accent-strong: "#8f86c9"
typography:
  display:
    fontFamily: "Geist, system-ui, sans-serif"
    fontSize: "clamp(2.5rem, 6.2vw, 5rem)"
    fontWeight: 550
    lineHeight: 1.02
    letterSpacing: "-0.032em"
  headline:
    fontFamily: "Geist, system-ui, sans-serif"
    fontSize: "clamp(1.625rem, 3.2vw, 2.375rem)"
    fontWeight: 550
    lineHeight: 1.1
    letterSpacing: "-0.024em"
  title:
    fontFamily: "Geist, system-ui, sans-serif"
    fontSize: "1.0625rem"
    fontWeight: 600
    lineHeight: 1.4
    letterSpacing: "-0.012em"
  lead:
    fontFamily: "Geist, system-ui, sans-serif"
    fontSize: "1.1875rem"
    fontWeight: 400
    lineHeight: 1.6
    letterSpacing: "-0.006em"
  body:
    fontFamily: "Geist, system-ui, sans-serif"
    fontSize: "0.9375rem"
    fontWeight: 400
    lineHeight: 1.65
    letterSpacing: "normal"
  label:
    fontFamily: "Geist, system-ui, sans-serif"
    fontSize: "0.8125rem"
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: "normal"
rounded:
  control: "10px"
  media: "12px"
  full: "999px"
spacing:
  gutter: "24px"
  section: "96px"
  section-lg: "128px"
  container: "1152px"
components:
  button-primary:
    backgroundColor: "{colors.foreground}"
    textColor: "{colors.background}"
    rounded: "{rounded.control}"
    padding: "10px 16px"
  button-primary-hover:
    backgroundColor: "#ffffff"
    textColor: "{colors.background}"
  button-secondary:
    backgroundColor: "transparent"
    textColor: "{colors.foreground}"
    rounded: "{rounded.control}"
    padding: "10px 16px"
  button-secondary-hover:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.foreground}"
  nav-link:
    backgroundColor: "transparent"
    textColor: "{colors.muted}"
    rounded: "{rounded.control}"
    padding: "6px 12px"
  nav-link-hover:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.foreground}"
  media-frame:
    backgroundColor: "transparent"
    rounded: "{rounded.media}"
---

# Design System: Snapwell Site

## Overview

**North star: the darkroom.** The page is a dark, quiet room whose only light
comes from the work pinned to the wall. Every surface is a neutral near-black;
every colour a visitor actually sees is a real screenshot, a real poster, a real
interior photo from somebody's Snapwell library. The interface recedes so the
collection reads.

This is the category standard for a native Mac app, chosen deliberately and
executed at full fidelity rather than decorated into something else. The craft
bar is Raycast: dense, precise, high-contrast, no ornament that isn't load-bearing.

Mood: quiet, exact, unhurried, technical without costume.

**Confirmed anti-reference:** the generic AI-startup landing page — warm gold or
terracotta accent on near-black, italic serif display phrases, tracked-out
monospace eyebrows, 01/02/03 numbered steps, hand-drawn abstract SVG icons, and
a scroll-locked multi-second hero animation. The previous version of this site
was all of those; none of them may return.

## Colors

Strategy: **restrained**. Neutrals plus one accent that is deliberately almost
never seen.

| Token | Value | Role |
|---|---|---|
| `background` | `#09090b` | Cool Near-Black. The single page ground; no section ever gets a different one. |
| `surface` | `#131316` | Raised Charcoal. Hover fills only. |
| `border` | `#232329` | Hairline. Every rule, divider, and media edge. |
| `border-strong` | `#34343c` | Hairline Lifted. Hover borders and scrollbar thumb. |
| `border-hover` | `#45454f` | Hairline Active. Scrollbar thumb on hover only. |
| `foreground` | `#f4f4f6` | Paper White. Body and headings; also the primary button's fill. |
| `muted` | `#9c9ca6` | Cool Grey. All secondary text. 7:1 on `background`. |
| `accent` | `#b7b2ce` | Icon Lavender, sampled from the app icon's shadow tones. |
| `accent-strong` | `#8f86c9` | Icon Lavender Deep. Focus rings, caret, selection. |

**The accent is held back on purpose.** It appears only in text selection, the
focus ring, the caret, and a single footer link. Colour on this page is the
product's own content. Do not spend the accent on eyebrows, rules, section
labels, or icon tints — that is exactly how the previous gold version failed.

## Typography

**One family: Geist.** No second face, no display serif, no monospace. The
previous site carried three families and used the serif italic decoratively;
that is the single loudest tell it had.

Six roles, applied as CSS classes in `globals.css`: `.t-display`, `.t-h2`,
`.t-h3`, `.t-lead`, `.t-body`, plus a 13px label size used inline.

- Section display type tops out at **5rem**. The homepage hero is the deliberate
  exception, scaling to **8rem** so the product promise owns the first viewport.
- Tracking tightens as size grows and stops at **-0.032em**; never past -0.04em.
- Weight steps are 400 / 550 / 600 only.
- Measure is capped: lead 44ch, body 68ch.
- `text-wrap: balance` on display and headline.

Monospace is not part of this system. If a filesystem path or code needs to
appear, set it in Geist and separate it with colour, not a costume face.

## Layout

- Container `max-w-6xl` (1152px), gutter `px-6` (24px), everything left-aligned.
  Alignment is left throughout — no centred sections.
- Section rhythm: `pt-24` / `md:pt-32`. Space above a heading always exceeds the
  space below it.
- Breakpoints: `sm` 640 (library grid goes 3-up), `md` 768 (steps go 3-up),
  `lg` 1024 (the iOS section splits into copy + device).
- Full-bleed media aligns its **visible** edge to the container, not its file
  edge: assets with baked transparent padding are re-matted to their content
  bounds so a screenshot's left edge lands on the headline's left edge.

## Elevation & Depth

Layered, not lifted. Depth comes from a hairline border or a soft shadow —
**never both on the same element.**

- Media that is itself a window (the Mac recording): shadow only.
  `0 36px 72px -16px rgba(0,0,0,0.9)`.
- Device renders with transparent surrounds (iPhone): `drop-shadow` only, so it
  follows the alpha silhouette. `0 28px 56px rgba(0,0,0,0.85)`.
- Flat content tiles (library crops): `1px` border only, no shadow.
- The homepage has no site header. The icon and wordmark sit directly above the
  hero statement so the first viewport reads as a single product introduction.

Shadows always carry a vertical offset and a soft blur. A zero-offset glow is
decoration and does not belong here.

## Shapes

- Controls: `10px`. Buttons and nav links. Not pills.
- Media and panels: `12px`.
- `full` (999px) is reserved for the scrollbar thumb — a browser surface, never
  a content shape. No pill-shaped buttons or cards.
- No other radii, and no fully square edges.
- Borders are always exactly `1px` in `border`. No coloured left-borders, no
  weights above 1px.

## Components

- **Primary button** — solid `foreground` on `background` text, brand mark at
  15px, `10px` radius. Exactly one per viewport region.
- **Secondary button** — 1px `border`, transparent fill; hover lifts the border
  to `border-strong` and fills with `surface`.
- **Hero wordmark** — app icon + wordmark above the manifesto. The App Store and
  source CTAs live once, beneath the hero description; they are not duplicated
  in nav.
- **Step row** — a 3-column grid under a single full-width hairline. Title at
  `.t-h3`, one line of `.t-body` muted. No numbers, no icons, no card container.
- **Content tile** — a bare 4:3 image with a 1px border, caption beneath.
  Never wrapped in a card, never given a background panel.
- **Fact list** — a two-column `<dl>` with hairline row separators; term at 14px
  medium in `foreground`, definition in `muted`.
- **Demo video** — muted, looping, `playsInline`, with a poster frame. Under
  `prefers-reduced-motion: reduce` it does not autoplay and shows an explicit
  play control over the poster.

**Browser surfaces are themed, not defaulted:** `::selection`, caret colour,
scrollbar track and thumb, `:focus-visible` ring (2px `accent-strong`, 3px
offset), and link underline offset all come from the palette.

## Do's and Don'ts

**Do**

- Let the product's own material carry every bit of colour on the page.
- Prove claims with real screenshots and real recordings; crop evidence out of
  genuine captures.
- Ship product imagery at `quality={90}` with an explicit `sizes` attribute.
  Next 16 locks `images.qualities` to `[75]` by default and silently coerces
  anything else, which turns UI text to mush; `qualities: [75, 90]` is declared
  in `next.config.ts` for this reason.
- Encode source assets near-lossless (webp q95) and let Next perform the single
  lossy pass. Two lossy passes on a text-bearing screenshot is visible.
- When a source asset is narrower than the srcset candidate Next would pick,
  over-declare `sizes` so it serves the full source in one hop. Otherwise Next
  downscales to a candidate and the browser downscales again — two resamples,
  and the asset reads soft even though it is nominally retina. The iPhone
  render (742px source at 280px display) is the worked example.
- Keep one entrance animation for the whole page, at first paint, staggered
  ~65ms, exponential ease-out, and visible by default without it.
- Verify what a crop actually contains before presenting it as proof.
- Scope privacy claims precisely: "no tracking **in the apps**" — the site
  itself runs analytics and a support widget.

**Don't**

- Don't add a kicker or eyebrow above any heading. Ever.
- Don't number steps 01/02/03 unless the sequence carries information.
- Don't reintroduce a second typeface, an italic serif accent, or monospace as
  decoration.
- Don't lock scrolling or gate content behind an entrance animation.
- Don't use abstract line-art SVG as a stand-in for illustration or product
  imagery.
- Don't put a 1px border under a wide soft shadow on the same element.
- Don't wrap content in cards to give it structure; use spacing and hairlines.
- Don't invent counts, testimonials, press, or pricing. There are none.
