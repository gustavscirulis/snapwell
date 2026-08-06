import type { Metadata } from "next";
import { Geist } from "next/font/google";
import { Analytics } from "@vercel/analytics/next";
import "./globals.css";
import DevTools from "./dev-tools";
import { IntercomWidget } from "./intercom-widget";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const DIRECTION_CONTRACT = `<!--
THESIS: The category standard for a native Mac app, executed at full craft rather than decorated. It refuses the arrangement it replaces: gold-on-black, italic-serif accents, tracked mono eyebrows, 01/02/03 steps, abstract line-art icons.
OWN-WORLD: Near-black cool ground (#09090B), hairline borders, one typeface (Geist) on a four-step scale. The lavender-grey accent (#B7B2CE), sampled from the app icon, is held back to selection, focus rings and one link — every colour a visitor actually sees comes from the collected work itself. No gradient text, no second hue, no decorative SVG.
STORY: A designer learns Snapwell tags their whole library automatically, sees the real search field and real collected items as proof, and downloads.
FIRST VIEWPORT: Hairline sticky header. Left-aligned headline at 5rem max, lead paragraph, solid near-white primary CTA. Below it the real macOS screen recording, full container width, playing search silently on loop. Mac and iOS are separate beats; the iPhone gets its own section.
FORM: Canon — the standing exit, taken deliberately over grounded candidate 4 (Specimen Sheet). Seed key 1dc04a19.
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, and DESIGN.md
-->`;

export const metadata: Metadata = {
  metadataBase: new URL("https://snapwell.co"),
  title: "Snapwell — AI-Powered Inspiration Library for Mac & iOS",
  description:
    "Collect images and videos, let AI organize them. Native library for macOS and iOS with content-based search.",
  alternates: {
    canonical: "/",
  },
  icons: {
    icon: "/icon.png",
    apple: "/icon.png",
  },
  openGraph: {
    title: "Snapwell — AI-Powered Inspiration Library for Mac & iOS",
    description:
      "Collect images and videos, let AI organize them. Native library for macOS and iOS.",
    url: "https://snapwell.co",
    siteName: "Snapwell",
    type: "website",
    images: [
      {
        url: "/preview.webp",
        width: 1200,
        height: 779,
        alt: "Snapwell app showing a grid of collected images organized by AI",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Snapwell — AI-Powered Inspiration Library for Mac & iOS",
    description:
      "Collect images and videos, let AI organize them. Native library for macOS and iOS.",
    images: ["/preview.webp"],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={`${geistSans.variable} h-full antialiased`}>
      <body className="min-h-full flex flex-col">
        <div hidden dangerouslySetInnerHTML={{ __html: DIRECTION_CONTRACT }} />
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{
            __html: JSON.stringify({
              "@context": "https://schema.org",
              "@type": "SoftwareApplication",
              name: "Snapwell",
              operatingSystem: "macOS, iOS",
              applicationCategory: "MultimediaApplication",
              description:
                "AI-powered inspiration library for macOS and iOS. Collect images and videos, let AI organize them.",
              offers: {
                "@type": "Offer",
                price: "0",
                priceCurrency: "USD",
              },
            }),
          }}
        />
        {children}
        <Analytics />
        <IntercomWidget />
        <DevTools />
      </body>
    </html>
  );
}
