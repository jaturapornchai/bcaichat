"use client";

import { useEffect, useState } from "react";
import QRCode from "qrcode";

interface QrCodeSvgProps {
  value: string;
  size?: number;
  darkColor?: string;
  lightColor?: string;
  className?: string;
}

export function QrCodeSvg({
  value,
  size = 180,
  darkColor = "#681F18",
  lightColor = "#FFFFFF",
  className = "",
}: QrCodeSvgProps) {
  const [svgMarkup, setSvgMarkup] = useState<string>("");

  useEffect(() => {
    let active = true;
    QRCode.toString(value || "BC_AI_CHAT", {
      type: "svg",
      width: size,
      margin: 1,
      color: {
        dark: darkColor,
        light: lightColor,
      },
    })
      .then((svg) => {
        if (active) setSvgMarkup(svg);
      })
      .catch(() => {
        if (active) setSvgMarkup("");
      });
    return () => {
      active = false;
    };
  }, [value, size, darkColor, lightColor]);

  if (!svgMarkup) {
    return (
      <div
        style={{ width: size, height: size }}
        className={`flex items-center justify-center rounded-xl border bg-white text-xs text-[var(--bc-muted)] ${className}`}
      >
        กำลังสร้าง QR...
      </div>
    );
  }

  return (
    <div
      style={{ width: size, height: size }}
      className={`overflow-hidden rounded-xl border border-[var(--bc-border)] bg-white p-1.5 shadow-sm ${className}`}
      dangerouslySetInnerHTML={{ __html: svgMarkup }}
    />
  );
}
