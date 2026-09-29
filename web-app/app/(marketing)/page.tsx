import type { Metadata } from "next";
import { Reveal } from "../_components/reveal";
import { HeroSection } from "./_components/hero-section";
import { AppShowcase } from "./_components/app-showcase";
import { RouteExplorer } from "./_components/route-explorer";
import { InteractiveDemo } from "./_components/interactive-demo";
import { DownloadCta } from "./_components/download-cta";

export const metadata: Metadata = {
  alternates: { canonical: "/" },
};

export default function HomePage() {
  return (
    <main className="flex flex-1 flex-col">
      <Reveal><HeroSection /></Reveal>
      <Reveal><AppShowcase /></Reveal>
      <Reveal><RouteExplorer /></Reveal>
      <Reveal><InteractiveDemo /></Reveal>
      <Reveal><DownloadCta /></Reveal>
    </main>
  );
}
