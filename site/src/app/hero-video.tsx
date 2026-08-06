"use client";

import { useEffect, useRef, useState } from "react";

/**
 * The Mac demo. Plays on its own, silently, unless the visitor has asked for
 * reduced motion — then it holds on the poster frame behind an explicit play
 * control.
 */
export function HeroVideo() {
  const ref = useRef<HTMLVideoElement>(null);
  const [manual, setManual] = useState(false);
  const [playing, setPlaying] = useState(false);

  useEffect(() => {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    setManual(reduce);
    if (!reduce) void ref.current?.play().catch(() => {});
  }, []);

  return (
    <div className="relative overflow-hidden rounded-xl shadow-[0_36px_72px_-16px_rgba(0,0,0,0.9)]">
      <video
        ref={ref}
        src="/video.mp4"
        poster="/hero/poster.webp"
        width={2518}
        height={1484}
        muted
        loop
        playsInline
        preload="metadata"
        aria-label="A screen recording of Snapwell on macOS: a grid of collected images and videos, then a search that finds items by their descriptions"
        className="block w-full"
        onPlay={() => setPlaying(true)}
        onPause={() => setPlaying(false)}
      />

      {manual && !playing && (
        <button
          type="button"
          onClick={() => void ref.current?.play()}
          className="absolute inset-0 flex items-center justify-center bg-background/40 transition-colors hover:bg-background/25"
        >
          <span className="inline-flex items-center gap-2 rounded-[10px] bg-foreground px-4 py-2.5 text-sm font-medium text-background">
            <svg viewBox="0 0 16 16" fill="currentColor" aria-hidden className="h-3.5 w-3.5">
              <path d="M4.5 2.6a.7.7 0 0 1 1.06-.6l7.2 5.4a.7.7 0 0 1 0 1.2l-7.2 5.4a.7.7 0 0 1-1.06-.6V2.6Z" />
            </svg>
            Play the demo
          </span>
        </button>
      )}
    </div>
  );
}
