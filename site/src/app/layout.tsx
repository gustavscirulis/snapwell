import type { Metadata } from "next";
import { Geist, Geist_Mono, Instrument_Serif } from "next/font/google";
import { Analytics } from "@vercel/analytics/next";
import "./globals.css";
import DevTools from "./dev-tools";
import { HeroGate } from "./hero-gate";
import { IntercomWidget } from "./intercom-widget";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

const instrumentSerif = Instrument_Serif({
  weight: "400",
  style: ["normal", "italic"],
  variable: "--font-display",
  subsets: ["latin"],
  display: "swap",
});

export const metadata: Metadata = {
  metadataBase: new URL("https://www.snapwell.co"),
  title: "Snapwell — AI-Powered Inspiration Library for Mac & iOS",
  description:
    "Collect images and videos, let AI organize them. Local-first library for macOS and iOS with content-based search.",
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
      "Collect images and videos, let AI organize them. Local-first library for macOS and iOS.",
    url: "https://www.snapwell.co",
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
      "Collect images and videos, let AI organize them. Local-first library for macOS and iOS.",
    images: ["/preview.webp"],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} ${instrumentSerif.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">
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
        <HeroGate />
        <IntercomWidget />
        <DevTools />
      </body>
    </html>
  );
}
