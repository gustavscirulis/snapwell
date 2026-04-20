"use client";

import { Agentation } from "agentation";

export default function DevTools() {
  if (process.env.NODE_ENV !== "development") return null;
  return <Agentation />;
}
