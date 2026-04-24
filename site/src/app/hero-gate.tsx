"use client";

import { useEffect } from "react";

const HERO_DURATION_MS = 6500;

export function HeroGate() {
  useEffect(() => {
    const timer = setTimeout(() => {
      document.documentElement.classList.add("hero-played");
    }, HERO_DURATION_MS);
    return () => clearTimeout(timer);
  }, []);
  return null;
}
