import type { ReactNode } from "react";
import { SiteShell } from "../_components/site-shell";

// Route-group layouts have no URL segment of their own, so the generated
// LayoutProps<'/route'> helper doesn't apply here — plain children prop.
export default function LegalLayout({ children }: { children: ReactNode }) {
  return (
    <SiteShell>
      <div className="mx-auto w-full max-w-3xl flex-1 px-5 py-16">
        {children}
      </div>
    </SiteShell>
  );
}
