import type { Metadata } from "next";
import { Geist, Geist_Mono, Instrument_Serif } from "next/font/google";
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
  title: "Snapwell — Your inspiration, organized by AI. An inspiration library for macOS and iOS.",
  description:
    "Collect images and videos, let AI organize them. Local-first library for macOS and iOS with content-based search.",
  icons: {
    icon: "/icon.png",
    apple: "/icon.png",
  },
  openGraph: {
    title: "Snapwell — Your inspiration, organized by AI. An inspiration library for macOS and iOS.",
    description:
      "Collect images and videos, let AI organize them. Local-first library for macOS and iOS.",
    type: "website",
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
        {children}
        <HeroGate />
        <IntercomWidget />
        <DevTools />
      </body>
    </html>
  );
}
