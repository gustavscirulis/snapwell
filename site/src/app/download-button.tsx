"use client";

import { useState, useRef, useEffect } from "react";

const platforms = [
  {
    label: "macOS",
    href: "https://github.com/gustavscirulis/snapwell/releases",
    note: "Requires macOS 15+",
  },
  {
    label: "iOS",
    href: "https://github.com/gustavscirulis/snapwell/releases",
    note: "Requires iOS 17+",
  },
];

export function DownloadButton({ className }: { className?: string }) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    function handleEscape(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }
    if (open) {
      document.addEventListener("mousedown", handleClickOutside);
      document.addEventListener("keydown", handleEscape);
    }
    return () => {
      document.removeEventListener("mousedown", handleClickOutside);
      document.removeEventListener("keydown", handleEscape);
    };
  }, [open]);

  return (
    <div ref={ref} className={`relative ${className ?? ""}`}>
      <button
        onClick={() => setOpen(!open)}
        aria-expanded={open}
        aria-haspopup="true"
        className="inline-flex items-center gap-2 rounded-full bg-accent px-6 py-3 text-sm font-medium text-white transition-all hover:brightness-110 hover:shadow-lg"
      >
        {"\uF8FF"} Download
        <svg
          width="12"
          height="12"
          viewBox="0 0 12 12"
          fill="none"
          className={`transition-transform duration-200 ${open ? "rotate-180" : ""}`}
        >
          <path
            d="M3 4.5L6 7.5L9 4.5"
            stroke="currentColor"
            strokeWidth="1.5"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
      </button>

      <div
        className={`absolute left-1/2 z-50 mt-2 min-w-[180px] -translate-x-1/2 overflow-hidden rounded-xl bg-surface shadow-xl ring-1 ring-border transition-all duration-200 ${
          open
            ? "visible scale-100 opacity-100"
            : "invisible scale-95 opacity-0"
        }`}
        role="menu"
      >
        {platforms.map((platform) => (
          <a
            key={platform.label}
            href={platform.href}
            role="menuitem"
            onClick={() => setOpen(false)}
            className="flex flex-col px-5 py-3 text-left transition-colors hover:bg-accent-soft first:rounded-t-xl last:rounded-b-xl"
          >
            <span className="whitespace-nowrap text-sm font-medium text-foreground">
              {platform.label}
            </span>
            <span className="text-xs text-muted">{platform.note}</span>
          </a>
        ))}
      </div>
    </div>
  );
}
