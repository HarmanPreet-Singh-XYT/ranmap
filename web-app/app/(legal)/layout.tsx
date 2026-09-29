import type { ReactNode } from "react";
import { SiteShell } from "../_components/site-shell";

// Route-group layouts have no URL segment of their own, so the generated
// LayoutProps<'/route'> helper doesn't apply here — plain children prop.
// Pages in this group render their own full-bleed header section (matching
// support/pricing/features), so the layout only supplies the shared shell.
export default function LegalLayout({ children }: { children: ReactNode }) {
  return <SiteShell>{children}</SiteShell>;
}
