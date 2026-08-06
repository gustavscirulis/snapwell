import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  images: {
    // Next 16 locks this to [75] by default and coerces any `quality` prop to
    // the nearest allowed value. Product screenshots carry fine UI text, so
    // they need a higher pass than the default.
    qualities: [75, 90],
  },
};

export default nextConfig;
