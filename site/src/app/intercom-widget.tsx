"use client";

import { useEffect } from "react";

declare global {
  interface Window {
    Intercom: any;
  }
}

const HERO_ANIMATION_DURATION_MS = 6500;

export function IntercomWidget() {
  useEffect(() => {
    const prefersReducedMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)"
    ).matches;
    const delay = prefersReducedMotion ? 0 : HERO_ANIMATION_DURATION_MS;

    const timer = setTimeout(() => {
      (function () {
        var w = window;
        var ic = w.Intercom;
        if (typeof ic === "function") {
          ic("reattach_activator");
        } else {
          var d = document;
          var i: any = function () {
            i.c(arguments);
          };
          i.q = [] as any[];
          i.c = function (args: any) {
            i.q.push(args);
          };
          w.Intercom = i;
          var l = function () {
            var s = d.createElement("script");
            s.type = "text/javascript";
            s.async = true;
            s.src = "https://widget.intercom.io/widget/zxw660qv";
            var x = d.getElementsByTagName("script")[0];
            x.parentNode!.insertBefore(s, x);
          };
          if (document.readyState === "complete") {
            l();
          } else {
            w.addEventListener("load", l, false);
          }
        }
      })();
      window.Intercom("boot", {
        api_base: "https://api-iam.intercom.io",
        app_id: "zxw660qv",
      });
    }, delay);

    return () => {
      clearTimeout(timer);
      if (window.Intercom) window.Intercom("shutdown");
    };
  }, []);
  return null;
}
