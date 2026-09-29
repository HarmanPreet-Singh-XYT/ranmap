import { ImageResponse } from "next/og";
import { siteDescription, siteName } from "@/lib/site";

export const alt = "Ranmap — Real-Time Convoy Navigation & Road-Trip Platform";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          height: "100%",
          width: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          background: "linear-gradient(135deg, #0b1220 0%, #0f172a 60%, #14532d 100%)",
          padding: "72px",
          color: "white",
          fontFamily: "sans-serif",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: "20px" }}>
          <div
            style={{
              display: "flex",
              width: "64px",
              height: "64px",
              borderRadius: "18px",
              background: "#15803d",
              alignItems: "center",
              justifyContent: "center",
              fontSize: "38px",
              fontWeight: 800,
            }}
          >
            R
          </div>
          <div style={{ display: "flex", fontSize: "40px", fontWeight: 800 }}>
            {siteName}
          </div>
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
          <div
            style={{
              display: "flex",
              fontSize: "76px",
              fontWeight: 800,
              lineHeight: 1.05,
            }}
          >
            Never lose the pack.
          </div>
          <div
            style={{
              display: "flex",
              fontSize: "34px",
              fontWeight: 700,
              color: "#4ade80",
            }}
          >
            Drive together in sync.
          </div>
        </div>

        <div
          style={{
            display: "flex",
            fontSize: "26px",
            color: "#94a3b8",
            maxWidth: "960px",
          }}
        >
          {siteDescription}
        </div>
      </div>
    ),
    { ...size },
  );
}
