import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Privacy Policy — Snapwell",
  description:
    "Snapwell privacy policy. Local-first media library — your files stay on your device.",
  alternates: {
    canonical: "/privacy",
  },
};

export default function PrivacyPage() {
  return (
    <>
      <main className="mx-auto max-w-2xl px-6 py-24 md:py-32">
        <Link
          href="/"
          className="mb-12 inline-flex items-center gap-1.5 text-sm text-muted transition-colors hover:text-foreground"
        >
          <svg
            width="16"
            height="16"
            viewBox="0 0 16 16"
            fill="none"
            className="shrink-0"
          >
            <path
              d="M10 12L6 8L10 4"
              stroke="currentColor"
              strokeWidth="1.5"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
          Back to Snapwell
        </Link>

        <h1 className="font-display text-4xl italic leading-tight md:text-5xl">
          Privacy Policy
        </h1>
        <p className="mt-4 text-sm text-muted">Last updated — April 24, 2026</p>

        <div className="mt-12 space-y-10 text-[15px] leading-relaxed text-muted [&_h2]:mb-3 [&_h2]:text-lg [&_h2]:font-medium [&_h2]:text-foreground [&_a]:text-foreground [&_a]:underline [&_a]:underline-offset-2 hover:[&_a]:text-accent [&_strong]:font-medium [&_strong]:text-foreground/80 [&_ul]:list-disc [&_ul]:space-y-1.5 [&_ul]:pl-5">
          <section>
            <h2>Overview</h2>
            <p>
              Snapwell is a <strong>local-first</strong> application. Your media
              files, metadata, and organizational structure are stored on your
              devices and your iCloud. We do not operate servers that collect,
              process, or store your content.
            </p>
          </section>

          <section>
            <h2>Data that stays yours</h2>
            <ul>
              <li>Images and videos you import</li>
              <li>AI-generated descriptions and tags</li>
              <li>Spaces, organization, and preferences</li>
              <li>Thumbnails and cached data</li>
            </ul>
            <p className="mt-3">
              On Mac, this lives in your local{" "}
              <strong>~/Documents/Snapwell/</strong> folder. On iOS, it syncs
              through your personal iCloud Drive. Either way, we never have
              access to it.
            </p>
          </section>

          <section>
            <h2>AI analysis</h2>
            <p>
              When you analyze media, Snapwell sends images to the AI provider
              you configure (e.g. OpenAI, Anthropic). These requests go{" "}
              <strong>directly from your device to the provider</strong> — they
              never pass through Snapwell infrastructure. Each provider&apos;s
              own privacy policy governs how they handle that data. You supply
              your own API key and can choose or change your provider at any
              time.
            </p>
          </section>

          <section>
            <h2>iCloud sync (iOS)</h2>
            <p>
              The iOS companion app uses Apple iCloud Drive to sync your Snapwell
              folder across devices. This sync is managed entirely by Apple
              under their{" "}
              <a
                href="https://www.apple.com/legal/privacy/"
                target="_blank"
                rel="noopener noreferrer"
              >
                privacy policy
              </a>
              . Snapwell does not operate any additional sync service.
            </p>
          </section>

          <section>
            <h2>Analytics &amp; telemetry</h2>
            <p>
              Snapwell does not include analytics SDKs, telemetry, or tracking
              of any kind. We do not collect usage data, crash reports, or device
              information.
            </p>
          </section>

          <section>
            <h2>Website</h2>
            <p>
              The Snapwell website (<strong>snapwell.co</strong>) is a static
              site. It does not use cookies or third-party trackers for
              analytics.
            </p>
          </section>

          <section>
            <h2>Open source</h2>
            <p>
              Snapwell is open source. You can inspect exactly what data the
              application accesses in the{" "}
              <a
                href="https://github.com/gustavscirulis/snapwell"
                target="_blank"
                rel="noopener noreferrer"
              >
                source code on GitHub
              </a>
              .
            </p>
          </section>

          <section>
            <h2>Contact</h2>
            <p>
              Questions about this policy? Send us a message using the chat
              widget at the bottom of this page.
            </p>
          </section>
        </div>
      </main>

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
