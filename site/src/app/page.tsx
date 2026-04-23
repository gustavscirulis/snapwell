import Image from "next/image";
import { ParallaxWrapper } from "./parallax-image";

const useCases = [
  {
    title: "UI design references",
    description:
      "Save every UI you screenshot, every pattern you bookmark. When you need that login flow you saw three weeks ago\u2009—\u2009describe it.",
    icon: (
      <svg width="48" height="48" viewBox="0 0 48 48" fill="none" className="text-accent">
        <rect x="4" y="4" width="12" height="12" stroke="currentColor" strokeWidth="0.8" opacity="0.5" />
        <rect x="20" y="4" width="12" height="12" stroke="currentColor" strokeWidth="0.8" opacity="0.35" />
        <rect x="36" y="4" width="8" height="8" stroke="currentColor" strokeWidth="0.8" opacity="0.2" />
        <rect x="4" y="20" width="12" height="12" stroke="currentColor" strokeWidth="0.8" opacity="0.35" />
        <rect x="20" y="20" width="12" height="12" stroke="currentColor" strokeWidth="0.8" opacity="0.2" />
        <rect x="4" y="36" width="8" height="8" stroke="currentColor" strokeWidth="0.8" opacity="0.15" />
        <rect x="10" y="10" width="6" height="6" fill="currentColor" opacity="0.12" />
      </svg>
    ),
  },
  {
    title: "Home & style projects",
    description:
      "Renovation ideas, furniture options, paint swatches. Drop everything into a space. Find the exact tile you saved in March by describing the color.",
    icon: (
      <svg width="48" height="48" viewBox="0 0 48 48" fill="none" className="text-accent">
        <rect x="8" y="14" width="20" height="26" rx="2" stroke="currentColor" strokeWidth="0.8" opacity="0.25" transform="rotate(-6 8 14)" />
        <rect x="16" y="8" width="20" height="26" rx="2" stroke="currentColor" strokeWidth="0.8" opacity="0.4" transform="rotate(3 16 8)" />
        <rect x="22" y="12" width="20" height="26" rx="2" stroke="currentColor" strokeWidth="0.8" opacity="0.55" transform="rotate(-2 22 12)" />
        <circle cx="32" cy="22" r="3" fill="currentColor" opacity="0.1" />
      </svg>
    ),
  },
  {
    title: "Creative inspiration",
    description:
      "Art, typography, photography, fashion. Import from anywhere, and search by what\u2019s in the image\u2009—\u2009not what you remembered to name it.",
    icon: (
      <svg width="48" height="48" viewBox="0 0 48 48" fill="none" className="text-accent">
        <path d="M4 40 Q24 -8 44 40" stroke="currentColor" strokeWidth="0.8" opacity="0.4" fill="none" />
        <path d="M4 8 Q24 56 44 8" stroke="currentColor" strokeWidth="0.8" opacity="0.3" fill="none" />
        <path d="M0 24 Q48 4 48 44" stroke="currentColor" strokeWidth="0.8" opacity="0.2" fill="none" />
        <circle cx="24" cy="24" r="4" stroke="currentColor" strokeWidth="0.8" opacity="0.4" />
        <circle cx="24" cy="24" r="1.5" fill="currentColor" opacity="0.2" />
      </svg>
    ),
  },
  {
    title: "Research & evidence",
    description:
      "Competitor pages, bug screenshots, visual audits. Everything is tagged and searchable the moment it lands\u2009—\u2009no folders, no renaming.",
    icon: (
      <svg width="48" height="48" viewBox="0 0 48 48" fill="none" className="text-accent">
        <circle cx="24" cy="24" r="18" stroke="currentColor" strokeWidth="0.8" opacity="0.2" />
        <circle cx="24" cy="24" r="12" stroke="currentColor" strokeWidth="0.8" opacity="0.35" />
        <circle cx="24" cy="24" r="6" stroke="currentColor" strokeWidth="0.8" opacity="0.5" />
        <line x1="24" y1="2" x2="24" y2="46" stroke="currentColor" strokeWidth="0.5" opacity="0.15" />
        <line x1="2" y1="24" x2="46" y2="24" stroke="currentColor" strokeWidth="0.5" opacity="0.15" />
        <circle cx="24" cy="24" r="2" fill="currentColor" opacity="0.2" />
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
              src="/hero/background.jpg"
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
                    src="/hero/mac.png"
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
                    src="/hero/iphone.png"
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
                  t: "Import from anywhere",
                  d: "Screenshots, photos, video, web images. Drag in, paste, or share from X.",
                },
                {
                  n: "02",
                  t: "AI tags everything",
                  d: "Every image gets analyzed automatically. Want more control? Add custom guidance to focus on what matters.",
                },
                {
                  n: "03",
                  t: "Search by what you see",
                  d: "Find images by what\u2019s in them, not what you named the file.",
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
                  className="group flex flex-col gap-4 py-9 first:border-t first:border-border sm:flex-row sm:items-start sm:gap-10"
                >
                  <div className="shrink-0 transition-transform group-hover:scale-105">
                    {uc.icon}
                  </div>
                  <h3 className="shrink-0 text-[22px] font-semibold leading-7 sm:w-[280px] sm:pt-2.5 md:w-[340px]">
                    {uc.title}
                  </h3>
                  <p className="text-[15px] leading-relaxed text-muted sm:pt-3">
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
              No servers.
              <br />
              No telemetry.
              <br />
              Open source.
            </h2>
            <div className="mx-auto mt-8 h-px w-16 bg-accent" />
            <p className="mt-8 text-muted md:text-lg">
              Every line of code is on GitHub under GPLv3. Everything stays on
              your device. AI analysis goes directly to your provider — API keys
              are AES-GCM encrypted. We never see your data.
            </p>
          </div>
        </section>

        {/* ── CTA ───────────────────────────────────────── */}
        <section className="px-6 py-32">
          <div className="mx-auto max-w-6xl">
            <div className="flex flex-col items-start gap-8 md:flex-row md:items-end md:justify-between">
              <div>
                <h2 className="font-display text-5xl md:text-6xl">
                  Snapwell
                </h2>
                <p className="mt-4 text-muted">
                  Free and open source under GPLv3.
                </p>
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
            <a
              href="mailto:privacy@snapwell.app"
              className="transition-colors hover:text-foreground"
            >
              Privacy
            </a>
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
