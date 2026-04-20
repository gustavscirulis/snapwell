import Image from "next/image";
import { ParallaxWrapper } from "./parallax-image";

const useCases = [
  {
    title: "UI & design references",
    description:
      "Screenshot interfaces, collect patterns, track visual systems. Search by what you see, not what you named the file.",
    illustration: (
      <svg width="56" height="44" viewBox="0 0 56 44" fill="none" className="text-accent">
        <rect x="1" y="1" width="54" height="34" rx="4" stroke="currentColor" strokeWidth="1.2" opacity="0.5" />
        <rect x="5" y="5" width="14" height="10" rx="2" fill="currentColor" opacity="0.2" />
        <rect x="21" y="5" width="14" height="10" rx="2" fill="currentColor" opacity="0.12" />
        <rect x="37" y="5" width="14" height="10" rx="2" fill="currentColor" opacity="0.08" />
        <rect x="5" y="18" width="14" height="10" rx="2" fill="currentColor" opacity="0.12" />
        <rect x="21" y="18" width="14" height="10" rx="2" fill="currentColor" opacity="0.08" />
        <rect x="37" y="18" width="14" height="10" rx="2" fill="currentColor" opacity="0.05" />
        <circle cx="12" cy="40" r="2" fill="currentColor" opacity="0.5" />
        <line x1="18" y1="40" x2="38" y2="40" stroke="currentColor" strokeWidth="1.2" opacity="0.2" />
      </svg>
    ),
  },
  {
    title: "Project inspiration",
    description:
      "Planning a renovation, picking furniture, collecting style references. Organize into spaces and let AI surface connections.",
    illustration: (
      <svg width="56" height="44" viewBox="0 0 56 44" fill="none" className="text-accent">
        <rect x="4" y="6" width="22" height="16" rx="3" stroke="currentColor" strokeWidth="1.2" opacity="0.3" transform="rotate(-4 4 6)" />
        <rect x="18" y="2" width="22" height="16" rx="3" stroke="currentColor" strokeWidth="1.2" opacity="0.5" transform="rotate(2 18 2)" />
        <rect x="10" y="20" width="28" height="20" rx="3" stroke="currentColor" strokeWidth="1.2" opacity="0.7" />
        <line x1="14" y1="34" x2="34" y2="34" stroke="currentColor" strokeWidth="1.2" opacity="0.3" />
        <line x1="14" y1="37" x2="26" y2="37" stroke="currentColor" strokeWidth="1.2" opacity="0.15" />
      </svg>
    ),
  },
  {
    title: "Mood boards & curation",
    description:
      "Gather visual inspiration from anywhere. Drag images, paste from the web, import from X/Twitter. AI groups and tags automatically.",
    illustration: (
      <svg width="56" height="44" viewBox="0 0 56 44" fill="none" className="text-accent">
        <rect x="2" y="10" width="20" height="26" rx="2" stroke="currentColor" strokeWidth="1.2" opacity="0.25" />
        <rect x="12" y="6" width="20" height="26" rx="2" stroke="currentColor" strokeWidth="1.2" opacity="0.4" />
        <rect x="22" y="2" width="20" height="26" rx="2" stroke="currentColor" strokeWidth="1.2" opacity="0.6" />
        <line x1="26" y1="8" x2="38" y2="8" stroke="currentColor" strokeWidth="1.2" opacity="0.3" />
        <rect x="26" y="12" width="12" height="8" rx="1.5" fill="currentColor" opacity="0.1" />
        <circle cx="48" cy="38" r="4" stroke="currentColor" strokeWidth="1.2" opacity="0.2" />
        <circle cx="48" cy="38" r="1.5" fill="currentColor" opacity="0.3" />
      </svg>
    ),
  },
  {
    title: "Design systems",
    description:
      "Capture component states, track UI patterns across products, maintain a visual inventory that's always searchable.",
    illustration: (
      <svg width="56" height="44" viewBox="0 0 56 44" fill="none" className="text-accent">
        <rect x="18" y="2" width="20" height="12" rx="3" stroke="currentColor" strokeWidth="1.2" opacity="0.7" />
        <line x1="24" y1="14" x2="14" y2="22" stroke="currentColor" strokeWidth="1.2" opacity="0.3" />
        <line x1="32" y1="14" x2="42" y2="22" stroke="currentColor" strokeWidth="1.2" opacity="0.3" />
        <rect x="4" y="22" width="18" height="10" rx="2.5" stroke="currentColor" strokeWidth="1.2" opacity="0.45" />
        <rect x="34" y="22" width="18" height="10" rx="2.5" stroke="currentColor" strokeWidth="1.2" opacity="0.45" />
        <line x1="13" y1="32" x2="13" y2="37" stroke="currentColor" strokeWidth="1.2" opacity="0.2" />
        <line x1="43" y1="32" x2="43" y2="37" stroke="currentColor" strokeWidth="1.2" opacity="0.2" />
        <rect x="6" y="37" width="14" height="5" rx="1.5" fill="currentColor" opacity="0.12" />
        <rect x="36" y="37" width="14" height="5" rx="1.5" fill="currentColor" opacity="0.12" />
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
              src="/hero/background.png"
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
                    width={1278}
                    height={850}
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
                    width={482}
                    height={851}
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
            <div className="mt-16 grid gap-x-16 gap-y-14 sm:grid-cols-2">
              {useCases.map((uc) => (
                <div key={uc.title} className="group">
                  <div className="mb-5 transition-transform group-hover:translate-x-1">
                    {uc.illustration}
                  </div>
                  <h3 className="text-xl font-semibold transition-colors group-hover:text-accent">
                    {uc.title}
                  </h3>
                  <p className="mt-3 text-sm leading-relaxed text-muted">
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
