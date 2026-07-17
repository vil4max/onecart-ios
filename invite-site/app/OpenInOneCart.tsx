"use client";

import { useEffect } from "react";

type OpenInOneCartProps = {
  appURL: string;
};

export function OpenInOneCart({ appURL }: OpenInOneCartProps) {
  useEffect(() => {
    const frame = window.requestAnimationFrame(() => {
      window.location.assign(appURL);
    });

    return () => window.cancelAnimationFrame(frame);
  }, [appURL]);

  return (
    <a className="open-button" href={appURL}>
      <span>Открыть OneCart</span>
      <span className="button-arrow" aria-hidden="true">
        →
      </span>
    </a>
  );
}
