import { HeroSection } from "./_components/hero-section";
import { AppShowcase } from "./_components/app-showcase";
import { RouteExplorer } from "./_components/route-explorer";
import { InteractiveDemo } from "./_components/interactive-demo";
import { DownloadCta } from "./_components/download-cta";

export default function HomePage() {
  return (
    <main className="flex flex-1 flex-col">
      <HeroSection />
      <AppShowcase />
      <RouteExplorer />
      <InteractiveDemo />
      <DownloadCta />
    </main>
  );
}
