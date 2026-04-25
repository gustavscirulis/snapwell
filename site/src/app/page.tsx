import Image from "next/image";
import Link from "next/link";
import { ParallaxWrapper } from "./parallax-image";

const useCases = [
  {
    title: "UI design",
    description:
      "UI patterns, login flows, component states, animations.",
    icon: (
      <svg width="64" height="64" viewBox="0 0 48 48" fill="none" className="text-accent">
        <rect x="4" y="4" width="17" height="22" rx="2" stroke="currentColor" strokeWidth="0.8" opacity="0.5" />
        <rect x="5" y="5" width="15" height="20" rx="1.5" fill="currentColor" opacity="0.06" />
        <rect x="25" y="4" width="19" height="12" rx="2" stroke="currentColor" strokeWidth="0.8" opacity="0.35" />
        <rect x="25" y="20" width="19" height="16" rx="2" stroke="currentColor" strokeWidth="0.8" opacity="0.25" />
        <rect x="26" y="21" width="17" height="14" rx="1.5" fill="currentColor" opacity="0.04" />
        <rect x="4" y="30" width="17" height="14" rx="2" stroke="currentColor" strokeWidth="0.8" opacity="0.35" />
      </svg>
    ),
  },
  {
    title: "Home improvements",
    description:
      "Interior design ideas, furniture, paint swatches, room layouts.",
    icon: (
      <svg width="64" height="64" viewBox="0 0 48 48" fill="none" className="text-accent">
        <g transform="rotate(-8 16 22)">
          <rect x="4" y="8" width="22" height="22" rx="2" stroke="currentColor" strokeWidth="0.8" opacity="0.2" />
          <line x1="8" y1="26" x2="22" y2="12" stroke="currentColor" strokeWidth="0.4" opacity="0.1" />
          <line x1="8" y1="22" x2="18" y2="12" stroke="currentColor" strokeWidth="0.4" opacity="0.08" />
          <line x1="12" y1="26" x2="22" y2="16" stroke="currentColor" strokeWidth="0.4" opacity="0.08" />
        </g>
        <g transform="rotate(3 24 24)">
          <rect x="13" y="10" width="22" height="22" rx="2" stroke="currentColor" strokeWidth="0.8" opacity="0.38" />
          <circle cx="20" cy="17" r="1.2" fill="currentColor" opacity="0.08" />
          <circle cx="28" cy="15" r="0.8" fill="currentColor" opacity="0.1" />
          <circle cx="24" cy="24" r="1" fill="currentColor" opacity="0.07" />
          <circle cx="18" cy="26" r="0.7" fill="currentColor" opacity="0.1" />
          <circle cx="30" cy="22" r="1.3" fill="currentColor" opacity="0.06" />
        </g>
        <g transform="rotate(-2 30 26)">
          <rect x="22" y="16" width="22" height="22" rx="2" stroke="currentColor" strokeWidth="0.8" opacity="0.55" />
          <rect x="25" y="19" width="16" height="10" rx="1.5" fill="currentColor" opacity="0.1" />
        </g>
      </svg>
    ),
  },
  {
    title: "Creative inspiration",
    description:
      "Art, typography, photography, fashion, video references.",
    icon: (
      <svg width="64" height="64" viewBox="0 0 48 48" fill="none" className="text-accent">
        <path d="M38 6C48 16 48 34 36 40C26 46 12 40 8 30C4 22 10 12 18 10C24 8 30 14 30 20C30 25 26 28 23 27" stroke="currentColor" strokeWidth="0.8" opacity="0.45" strokeLinecap="round" fill="none" />
        <line x1="4" y1="16" x2="44" y2="16" stroke="currentColor" strokeWidth="0.5" opacity="0.2" />
        <line x1="4" y1="32" x2="44" y2="32" stroke="currentColor" strokeWidth="0.5" opacity="0.2" />
        <line x1="16" y1="4" x2="16" y2="44" stroke="currentColor" strokeWidth="0.5" opacity="0.2" />
        <line x1="32" y1="4" x2="32" y2="44" stroke="currentColor" strokeWidth="0.5" opacity="0.2" />
        <circle cx="23" cy="27" r="2" fill="currentColor" opacity="0.12" />
      </svg>
    ),
  },
];

export default function Home() {
  return (
    <>
      {/* ── Hero ──────────────────────────────────────── */}
      <header className="relative">
        <div className="relative z-20 px-6 pt-32 md:pt-44">
          <div className="mx-auto max-w-6xl">
            <p className="hero-text-1 font-mono text-xs uppercase tracking-[0.3em] text-accent">
              Open source · Local-first · AI-native
            </p>
            <h1 className="mt-8 pb-2 font-display text-[clamp(3rem,10vw,9rem)] leading-[0.85] tracking-tight">
              <span className="hero-headline">Your inspiration</span>
              <br />
              <span className="hero-tagline-reveal italic text-accent">
                organized by AI
              </span>
            </h1>
            <p className="hero-text-3 mt-6 max-w-md text-lg text-muted md:text-xl">
              Collect anything, search by what you see.
              <br />An inspiration library for macOS and iOS.
            </p>
            <div className="hero-text-4 mt-10 flex items-center gap-4">
              <span className="inline-flex items-center rounded-full border border-accent/40 px-6 py-3 text-sm font-medium text-accent">
                Coming soon
              </span>
              <a
                href="https://github.com/gustavscirulis/snapwell"
                className="rounded-full border border-border px-7 py-3 text-sm font-medium text-foreground transition-colors hover:bg-surface"
              >
                GitHub
              </a>
            </div>
          </div>
        </div>

        <div className="relative z-10 mt-16 pb-16">
          <div className="hero-bg-reveal absolute inset-0 overflow-hidden">
            <Image
              src="/hero/background.webp"
              alt=""
              fill
              className="object-cover opacity-50"
            />
            <div className="absolute inset-0 bg-gradient-to-t from-background via-background/50 to-background/20" />
            <div className="absolute inset-0 bg-gradient-to-r from-background/40 via-transparent to-background/40" />
          </div>

          <div className="relative mx-auto max-w-5xl px-6 pt-8">
            <div className="relative">
              <div className="hero-mac relative z-10">
                <ParallaxWrapper speed={0.5}>
                  <Image
                    src="/hero/mac.webp"
                    alt="Snapwell on Mac — a grid of collected images with AI-generated tags and search"
                    width={2556}
                    height={1700}
                    className="w-full drop-shadow-[0_32px_64px_rgba(0,0,0,0.4)]"
                    priority
                  />
                </ParallaxWrapper>
              </div>
              <div className="hero-iphone absolute -bottom-[14%] right-[-6%] z-20 w-[30%] md:right-[-2%] md:w-[28%]">
                <ParallaxWrapper speed={1.5}>
                  <Image
                    src="/hero/iphone.webp"
                    alt="Snapwell on iOS — the same library synced to your phone"
                    width={963}
                    height={1701}
                    className="w-full drop-shadow-[0_24px_48px_rgba(0,0,0,0.5)]"
                  />
                </ParallaxWrapper>
              </div>
            </div>
          </div>
        </div>
      </header>

      <main>
        {/* ── How it works ──────────────────────────────── */}
        <section className="px-6 py-32 md:py-40">
          <div className="mx-auto max-w-6xl">
            <p className="font-mono text-xs uppercase tracking-[0.3em] text-accent">
              How it works
            </p>
            <div className="mt-12 grid gap-16 md:grid-cols-3 md:gap-12">
              {[
                {
                  n: "01",
                  t: "Import images and videos",
                  d: "Screenshots, photos, video, web images. Drag in, paste, or share from any app.",
                },
                {
                  n: "02",
                  t: "AI tags everything",
                  d: "Every image gets analyzed automatically. Add guidance to focus on what matters to you.",
                },
                {
                  n: "03",
                  t: "Search by what you see",
                  d: "Describe an object, a layout, a mood. Snapwell finds the match\u2009—\u2009no tags or folders needed.",
                },
              ].map((step) => (
                <div key={step.n}>
                  <div className="h-px w-12 bg-accent" />
                  <span className="mt-4 block font-display text-3xl italic text-accent">
                    {step.n}
                  </span>
                  <h3 className="mt-3 text-lg font-semibold">{step.t}</h3>
                  <p className="mt-2 text-sm leading-relaxed text-muted">
                    {step.d}
                  </p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* ── Use cases ─────────────────────────────────── */}
        <section className="px-6 py-24 md:py-32">
          <div className="mx-auto max-w-6xl">
            <p className="font-mono text-xs uppercase tracking-[0.3em] text-accent">
              Use cases
            </p>
            <h2 className="mt-4 font-display text-3xl md:text-4xl">
              Built for{" "}
              <span className="italic text-accent">visual thinkers</span>
            </h2>
            <div className="mt-16 divide-y divide-border">
              {useCases.map((uc) => (
                <div
                  key={uc.title}
                  className="group flex flex-col gap-4 py-9 first:border-t first:border-border sm:flex-row sm:items-center sm:gap-10"
                >
                  <div className="shrink-0 transition-transform group-hover:scale-105">
                    {uc.icon}
                  </div>
                  <h3 className="shrink-0 text-[22px] font-semibold leading-7 sm:w-[280px] md:w-[340px]">
                    {uc.title}
                  </h3>
                  <p className="text-[15px] leading-relaxed text-muted">
                    {uc.description}
                  </p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* ── Privacy & open source ─────────────────────── */}
        <section className="bg-accent-soft px-6 py-32 md:py-48">
          <div className="mx-auto max-w-4xl text-center">
            <h2 className="font-display text-5xl italic leading-[1.1] md:text-7xl">
              No subscription.
              <br />
              No account.
              <br />
              Open source.
            </h2>
            <div className="mx-auto mt-8 h-px w-16 bg-accent" />
            <p className="mt-8 text-muted md:text-lg">
              Your library lives on your devices and your iCloud — not our servers.
              <br />
              AI analysis goes directly to the provider you choose.
            </p>
          </div>
        </section>

        {/* ── CTA ───────────────────────────────────────── */}
        <section className="px-6 py-32">
          <div className="mx-auto max-w-6xl">
            <div className="flex flex-col items-start gap-8 md:flex-row md:items-center md:justify-between">
              <div>
                <div className="flex items-start gap-6">
                  <Image
                    src="/icon.png"
                    alt=""
                    width={160}
                    height={160}
                    className="w-16 h-16 md:w-20 md:h-20 -mt-2 drop-shadow-[0_2px_20px_rgba(196,164,122,0.15)]"
                  />
                  <div>
                    <h2 className="font-display text-5xl md:text-6xl">
                      Snapwell
                    </h2>
                    <p className="mt-2 text-sm text-muted">
                      An open-source inspiration library for macOS and iOS. No account, no data collection.
                    </p>
                  </div>
                </div>
              </div>
              <div className="flex items-center gap-4">
                <span className="inline-flex items-center rounded-full border border-accent/40 px-6 py-3 text-sm font-medium text-accent">
                  Coming soon
                </span>
                <a
                  href="https://github.com/gustavscirulis/snapwell"
                  className="rounded-full border border-border px-7 py-3 text-sm font-medium transition-colors hover:bg-surface"
                >
                  GitHub
                </a>
              </div>
            </div>
          </div>
        </section>
      </main>

      {/* ── Footer ──────────────────────────────────────── */}
      <footer className="mt-auto border-t border-border px-6 py-8">
        <div className="mx-auto flex max-w-6xl flex-col gap-4 text-xs text-muted sm:flex-row sm:items-center sm:justify-between">
          <div className="flex gap-6">
            <Link
              href="/privacy"
              className="transition-colors hover:text-foreground"
            >
              Privacy
            </Link>
            <a
              href="https://github.com/gustavscirulis/snapwell"
              className="transition-colors hover:text-foreground"
            >
              GitHub
            </a>
          </div>
          <span>
            Built by{" "}
            <a
              href="https://x.com/gustavscirulis"
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
