import Image from "next/image";
import Link from "next/link";
import { HeroVideo } from "./hero-video";

const APP_STORE = "https://apps.apple.com/us/app/snapwell/id6762541353";
const GITHUB = "https://github.com/gustavscirulis/snapwell";

const steps = [
  {
    title: "Collect anything",
    body: "Screenshots, photos, video, images off the web. Drag in, paste, or share from any app on Mac and iPhone.",
  },
  {
    title: "AI describes and tags it",
    body: "AI writes a description and tags for every item on its own, in the background. Add per-space guidance to point it at what you care about.",
  },
  {
    title: "Find it by describing it",
    body: "Search for an object, a layout, a mood. Nothing to tag, nothing to file, nothing to remember.",
  },
];

const library = [
  {
    src: "/library/ui.webp",
    alt: "A product interface with a sidebar, a conversation panel and a structured procedure editor",
    title: "UI design",
    body: "Patterns, flows, states, animations.",
  },
  {
    src: "/library/interior.webp",
    alt: "A living room with a slatted walnut feature wall, concealed lighting and a low black console",
    title: "Home projects",
    body: "Interiors, furniture, paint, layouts.",
  },
  {
    src: "/library/creative.webp",
    alt: "An abstract 3D composition of a sphere, slab and disc in warm and cool gradients",
    title: "Creative reference",
    body: "Art, typography, photography, film.",
  },
];

const facts = [
  { k: "Price", v: "Free. No trial, no paid tier." },
  { k: "Storage", v: "Plain files in your Documents folder." },
  { k: "Sync", v: "Your own iCloud, Mac to iPhone." },
  { k: "Analysis", v: "Your own API key, or Ollama on your Mac." },
  { k: "Tracking", v: "None in the apps. No telemetry." },
  { k: "Platforms", v: "macOS 15+, iOS 17+, iPhone and iPad." },
];

function AppleMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 384 512" fill="currentColor" aria-hidden className={className}>
      <path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184.8 4 273.5q0 39.3 14.4 81.2c12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z" />
    </svg>
  );
}

function GitHubMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor" aria-hidden className={className}>
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27s1.36.09 2 .27c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8z" />
    </svg>
  );
}

function PrimaryCTA({ className = "" }: { className?: string }) {
  return (
    <a
      href={APP_STORE}
      className={`inline-flex items-center gap-2 rounded-[10px] bg-foreground px-4 py-2.5 text-sm font-medium text-background transition-colors hover:bg-white ${className}`}
    >
      <AppleMark className="h-[15px] w-[15px]" />
      Download on the App Store
    </a>
  );
}

function SecondaryCTA({ className = "" }: { className?: string }) {
  return (
    <a
      href={GITHUB}
      className={`inline-flex items-center gap-2 rounded-[10px] border border-border px-4 py-2.5 text-sm font-medium text-foreground transition-colors hover:border-border-strong hover:bg-surface ${className}`}
    >
      <GitHubMark className="h-[15px] w-[15px]" />
      View source
    </a>
  );
}

export default function Home() {
  return (
    <>
      <main>
        {/* ── Hero ──────────────────────────────────────────── */}
        <section className="px-6 pt-8 md:pt-12">
          <div className="mx-auto max-w-6xl">
            <Link
              href="/"
              aria-label="Snapwell home"
              className="rise inline-flex items-center gap-2.5"
              style={{ "--i": 0 } as React.CSSProperties}
            >
              <Image src="/icon.png" alt="" width={64} height={64} className="h-7 w-7" priority />
              <span className="text-[17px] font-semibold tracking-[-0.015em]">Snapwell</span>
            </Link>

            <div className="mt-20 md:mt-28">
              <h1
                className="rise max-w-[13ch] text-[clamp(3.75rem,9.2vw,8rem)] leading-[0.91] font-[550] tracking-[-0.058em] text-balance"
                style={{ "--i": 1 } as React.CSSProperties}
              >
                Everything you save, tagged automatically.
              </h1>

              <div className="rise mt-10 md:mt-12" style={{ "--i": 2 } as React.CSSProperties}>
                <p className="max-w-[44ch] text-[17px] leading-[1.6] tracking-[-0.008em] text-muted md:text-[19px]">
                  AI describes and tags every image and video you save —
                  automatically, in the background. Find anything by what&rsquo;s in
                  it, not what it&rsquo;s called. Native on Mac and iPhone.
                </p>
                <div className="mt-7 flex flex-wrap items-center gap-3">
                  <PrimaryCTA />
                  <SecondaryCTA />
                </div>
                <p className="mt-5 text-[13px] leading-relaxed text-muted">
                  Completely free · Open source · macOS 15+ · iOS 17+
                </p>
              </div>
            </div>

            <div
              className="rise relative left-1/2 mt-24 w-[min(1440px,calc(100vw-32px))] -translate-x-1/2 md:mt-32"
              style={{ "--i": 3 } as React.CSSProperties}
            >
              <HeroVideo />
            </div>
          </div>
        </section>

        {/* ── How it works ──────────────────────────────────── */}
        <section className="px-6 pt-24 md:pt-32">
          <div className="mx-auto max-w-6xl">
            <h2 className="t-h2">How it works</h2>

            <div className="mt-12 grid gap-10 border-t border-border pt-10 md:grid-cols-3 md:gap-12">
              {steps.map((step) => (
                <div key={step.title}>
                  <h3 className="t-h3">{step.title}</h3>
                  <p className="t-body mt-2.5 text-muted">{step.body}</p>
                </div>
              ))}
            </div>

          </div>
        </section>

        {/* ── iOS ───────────────────────────────────────────── */}
        <section className="px-6 pt-24 md:pt-32">
          <div className="mx-auto grid max-w-6xl items-center gap-12 lg:grid-cols-[1fr_auto] lg:gap-20">
            <div>
              <h2 className="t-h2">The same library, on your phone</h2>
              <p className="t-body mt-5 text-muted">
                Send images and video to Snapwell straight from the share sheet
                in any app — Safari, Photos, Instagram, anywhere. Everything
                moves over your own iCloud, so whatever you save on your phone
                is already there the next time you open your Mac. Analysis runs
                on iOS too.
              </p>
              <dl className="mt-8 flex flex-col gap-3 text-sm sm:flex-row sm:gap-10">
                <div>
                  <dt className="font-medium">Share extension</dt>
                  <dd className="mt-0.5 text-muted">Save from any app</dd>
                </div>
                <div>
                  <dt className="font-medium">iCloud sync</dt>
                  <dd className="mt-0.5 text-muted">Your account, not ours</dd>
                </div>
                <div>
                  <dt className="font-medium">iOS 17+</dt>
                  <dd className="mt-0.5 text-muted">iPhone and iPad</dd>
                </div>
              </dl>
            </div>

            <Image
              src="/hero/iphone.webp"
              alt="Snapwell on iPhone — the same collected library, synced over iCloud"
              width={742}
              height={1512}
              quality={90}
              // The device is only 742px wide at source. Over-declaring sizes
              // makes Next serve that full width in one hop, so the browser
              // does a single clean downscale instead of resampling twice.
              sizes="(min-width: 1024px) 380px, 300px"
              className="w-[220px] justify-self-start drop-shadow-[0_28px_56px_rgba(0,0,0,0.85)] lg:w-[280px] lg:justify-self-end"
            />
          </div>
        </section>

        {/* ── What people keep in it ────────────────────────── */}
        <section className="px-6 pt-24 md:pt-32">
          <div className="mx-auto max-w-6xl">
            <h2 className="t-h2">What people keep in it</h2>

            <div className="mt-12 grid gap-x-8 gap-y-12 sm:grid-cols-3">
              {library.map((item) => (
                <div key={item.title}>
                  <Image
                    src={item.src}
                    alt={item.alt}
                    width={1200}
                    height={900}
                    quality={90}
                    sizes="(min-width: 640px) 33vw, 100vw"
                    className="aspect-[4/3] w-full rounded-xl border border-border object-cover"
                  />
                  <h3 className="t-h3 mt-4">{item.title}</h3>
                  <p className="t-body mt-1.5 text-muted">{item.body}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* ── Custody ───────────────────────────────────────── */}
        <section className="px-6 pt-24 md:pt-32">
          <div className="mx-auto max-w-6xl">
            <h2 className="t-h2">Free. No account. No subscription.</h2>
            <p className="t-body mt-5 text-muted">
              Nothing to cancel, and nothing anyone can take away. Bring your
              own key for OpenAI, Claude, Gemini, or OpenRouter — or run Ollama
              locally on your Mac.
            </p>

            <dl className="mt-12 grid gap-x-10 border-t border-border lg:grid-cols-2">
              {facts.map((fact) => (
                <div
                  key={fact.k}
                  className="flex flex-col gap-1 border-b border-border py-5 sm:flex-row sm:gap-6"
                >
                  <dt className="shrink-0 text-sm font-medium sm:w-28">{fact.k}</dt>
                  <dd className="text-sm leading-relaxed text-muted">{fact.v}</dd>
                </div>
              ))}
            </dl>
          </div>
        </section>

        {/* ── Close ─────────────────────────────────────────── */}
        <section className="px-6 pt-24 pb-24 md:pt-32 md:pb-32">
          <div className="mx-auto max-w-6xl border-t border-border pt-16">
            <Image
              src="/icon.png"
              alt=""
              width={160}
              height={160}
              className="h-16 w-16"
            />
            <h2 className="t-h2 mt-6 max-w-[20ch]">
              Start with the images and videos you already have.
            </h2>
            <p className="t-body mt-4 text-muted">
              Import them to Snapwell and AI will do the analysis.
            </p>
            <div className="mt-8 flex flex-wrap items-center gap-3">
              <PrimaryCTA />
              <SecondaryCTA />
            </div>
            <p className="mt-5 text-[13px] text-muted">
              Free, with no account to create.
            </p>
          </div>
        </section>
      </main>

      <footer className="mt-auto border-t border-border px-6 py-8">
        <div className="mx-auto flex max-w-6xl flex-col gap-4 text-[13px] text-muted sm:flex-row sm:items-center sm:justify-between">
          <div className="flex gap-6">
            <Link href="/privacy" className="transition-colors hover:text-foreground">
              Privacy
            </Link>
            <a href={GITHUB} className="transition-colors hover:text-foreground">
              GitHub
            </a>
          </div>
          <span>
            Built by{" "}
            <a
              href="https://gustavscirulis.com"
              className="text-foreground transition-colors hover:text-accent"
            >
              Gustavs Cirulis
            </a>
          </span>
        </div>
      </footer>
    </>
  );
}
