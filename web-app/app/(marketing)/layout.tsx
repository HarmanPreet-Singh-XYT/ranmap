import type { ReactNode } from "react";
import { SiteShell } from "../_components/site-shell";

// Route-group layouts have no URL segment of their own, so the generated
// LayoutProps<'/route'> helper doesn't apply here — plain children prop.
export default function MarketingLayout({ children }: { children: ReactNode }) {
  return <SiteShell>{children}</SiteShell>;
}
